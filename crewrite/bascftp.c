/*
Copyright (c) 2023-2024, Vlad Meșco

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/
#define _XOPEN_SOURCE 600
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <unistd.h>
#include <errno.h>
#include <err.h>
#include <dirent.h>
#include <fcntl.h>
#include <sys/stat.h>

#include "crc.h"

#define VERSION "3.3c"

// signature for file hasher
typedef char* (*hash_f_t)(FILE*);

// directory job stack
struct DirNode {
    char* path;
    struct DirNode* next;
};

void help(const char* argv0)
{
    printf( "bascftp %s\n"
            "Usage: %s [help|ls|tree|put|get|version]\n"
            "    help                  prints this message\n"
            "    version               prints version\n"
            "    ls path               list directory\n"
            "    ls path md5           list directory and calculate md5 for files\n"
            "    tree path [md5]       same as ls, but recursive\n"
            "    put start end path    receives a chunk of a file on stdin\n"
            "    get start end path    returns a chunk of a file on stdout\n"
            "\n"
            "ls format:\n"
            "- directories:\n"
            "      d unixtime path\n"
            "- files:\n"
            "      f unixtime sizeinbytes hash path\n"
            "hash is 0 if not requested\n"
            "Example:\n"
            "      d 1666266539 subdir\n"
            "      f 1666266539 2279 2164e12fc5f03902b61d977fc2f29d00 file\n"
            ,
            VERSION,
            argv0);
    exit(1);
}

/** rmkdir: recursive mkdir
 *
 * rmkdir will ensure all directories for path exist.
 * If path does not end in a slash, the leaf name will be considered to be
 * a file you want to write, so it will not create a directory with that name
 */
int rmkdir(const char* path)
{
    if(!path) abort();
    if(!*path) return -1;
    const char* p1 = path; // points to next slash
    const char* pend = path + strlen(path); // end of input string
    char* tmp = strdup(path); // temporary dup to be able to progressively 
                              // NULL out slashes to pass to mkdir(2)

    // skip over initial slash(es)
    while(*p1 == '/') ++p1;
    // try to ignore duplicate slashes, but this is half arsed
    while(tmp[0] == '/' && tmp[1] == '/') ++tmp;
    
    // while we still have chars...
    while(p1 < pend) {
        // skip to next slash (if any)
        while(*p1 != '/' && *p1) ++p1;
        // if it's a slash
        if(*p1 == '/') {
            // temporarily null it out
            tmp[p1 - path] = '\0';
            if(-1 == mkdir(tmp, 0755)) {
                if(errno == EEXIST) {
                    // NOOP
                } else {
                    warn("Failed to create %s", tmp);
                    free(tmp);
                    return -1;
                }
            }
            // put the slash back
            tmp[p1 - path] = '/';
        }
        // skip slashes
        while(*p1 == '/') ++p1;
    }

    free(tmp);
    
    return 0;
}

void do_put(const char* path, ssize_t start, ssize_t end)
{
    FILE* f = NULL;

    // ensure all directory paths exist
    rmkdir(path);

    // check for empty file uploads
    if(start == 0 && start == end) {
        f = fopen(path, "w");
        if(!f) {
            fprintf(stderr, "Failed to write %s\n", path);
            exit(1);
        }
        fclose(f);
        exit(0);
    }

    // check how many bytes we're supposed to write
    ssize_t count = end - start;
    if(count < 0) {
        fprintf(stderr, "Incorrect range: %zd < %zd\n", end, start);
        exit(1);
    }

    // if this is the first block, blank out the file
    if(start == 0) {
        f = fopen(path, "w");
    } else {
        f = fopen(path, "r+");
    }

    if(!f) {
        fprintf(stderr, "Failed to open %s for writing\n", path);
        exit(1);
    }

    // truncate file to where we start writing;
    // see test "backfill second block, discarding 3rd"
    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    if(size < start) {
        if(-1 == ftruncate(fileno(f), start))
            err(1, "Failed to resize file %s to %ld", path, start);
    }
    fseek(f, start, SEEK_SET);

    // stream loop
    u_int8_t buf[8096];
    size_t totalReceived = 0;
    while(!feof(stdin)) {
        size_t toRead = (count - totalReceived < sizeof(buf)) ? count - totalReceived : sizeof(buf);
        size_t read = fread(buf, 1, toRead, stdin);
        if(read == 0 && ferror(stdin)) {
            fprintf(stderr, "Failed to read from standard input\n");
            exit(1);
        }
        if(read == 0) break;
        totalReceived += read;
        size_t written = fwrite(buf, 1, read, f);
        if(written != read) {
            fprintf(stderr, "Failed to write to %s\n", path);
            exit(1);
        }
        if(totalReceived >= count) break;
    }

    // see test "backfill second block, discarding 3rd"
    size = ftell(f);
    if(-1 == ftruncate(fileno(f), size)) {
        err(1, "Failed to truncate file %s at %ld\n", path, size);
    }

    fclose(f);
    exit(0);
}

void do_get(const char* path, off_t start, off_t end)
{
    FILE* f = NULL;

    // check how many bytes we're asked to fetch
    ssize_t count = end - start;
    if(count <= 0) {
        fprintf(stderr, "Incorrect range: %zd <= %zd\n", end, start);
        exit(1);
    }

    f = fopen(path, "r");
    if(!f) {
        fprintf(stderr, "Failed to open %s for reading\n", path);
        exit(1);
    }
    fseek(f, 0, SEEK_END);
    long pos = ftell(f);
    if(pos < start) {
        fprintf(stderr, "Bad range\n");
        exit(1);
    }
    if(pos < end) end = pos;

    count = end - start;

    fseek(f, start, SEEK_SET);

    // stream loop
    u_int8_t buf[8096];
    size_t totalSent = 0;
    while(!feof(stdin)) {
        size_t toRead = (count - totalSent < sizeof(buf)) ? count - totalSent : sizeof(buf);
        size_t read = fread(buf, 1, toRead, f);
        if(read == 0 && ferror(f)) {
            fprintf(stderr, "Failed to read from %s\n", path);
            exit(1);
        }
        if(read == 0) break;
        totalSent += read;
        size_t totalWritten = 0;
        while(totalWritten < read && !feof(stdout)) {
            size_t written = fwrite(buf, 1, read, stdout);
            if(written == 0 && ferror(stdout)) {
                fprintf(stderr, "Failed to write to stdout\n");
                exit(1);
            }
            totalWritten += written;
        }
        if(totalSent >= count) break;
    }

    fclose(f);
    exit(0);
}

// callback for crc32
char* crc32_hash(FILE* f)
{
    u_int8_t block[8096];
    fseek(f, 0, SEEK_SET);

    struct CKSUMContext cksum;
    CKSUM_Init(&cksum);

    while(!feof(f)) {
        size_t read = fread(block, 1, sizeof(block), f);
        if(read == 0 && ferror(f))
            return NULL;
        if(read == 0) break;
        CKSUM_Update(&cksum, block, read);
    }
    CKSUM_Final(&cksum);

    char* s = (char*)block;
    snprintf(s, 8096, "%u", cksum.crc);

    return strdup(s);
}

typedef enum {
    FAILED = -1,
    OK = 0,
    ISDIR = 1,
} STAT_RESULT;

STAT_RESULT stat_impl(const char* path, hash_f_t hash_fn)
{
    FILE* f = fopen(path, "r");
    if(!f) {
        fprintf(stderr, "Failed to open %s for reading\n", path);
        return FAILED;
    }
    int fd = fileno(f);
    struct stat sb;

    if(-1 ==  fstat(fd, &sb)) {
        warn("fstat %s failed", path);
        fclose(f);
        return FAILED;
    }

    time_t ftime = sb.st_mtime;

	if(S_ISDIR(sb.st_mode)) {
        printf("d %lu %s\n",
                (unsigned long)ftime,
                path);
        fclose(f);
        return ISDIR;
	} else if(!S_ISREG(sb.st_mode)) {
        // just... don't worry about pipes or devices, that's not
        // why we're here
        fprintf(stderr, "%s is not a file nor dir\n",
                path);
        fclose(f);
        return FAILED;
    }

    off_t fsize = sb.st_size;
	char* hash = NULL;

    // if we're asked to hash, hash
    if(hash_fn) {
		hash = hash_fn(f);
        if(!hash) {
            fprintf(stderr, "Failed to hash %s\n",
                    path);
        }
    }

	printf("f %lu %lu %s %s\n",
            (unsigned long)ftime,
            (unsigned long)fsize,
            hash ? hash : "0",
            path);
    fclose(f);
    if(hash) free(hash);

    return OK;
}

void do_ls(const char* path, const char* hash)
{
    hash_f_t hash_fn = (strcmp(hash, "crc32") == 0) ? crc32_hash : NULL;

    DIR* dp = opendir(path);
    if(!dp) {
        err(1, "opendir %s", path);
    }

    size_t npath = strlen(path);
    struct dirent* de;

    while((de = readdir(dp)) != NULL) {
        if(strcmp(de->d_name, "..") == 0) continue;
        if(strcmp(de->d_name, ".") == 0) continue;
        // TODO have option to exclude dot files
        char* fullpath = malloc(npath + 1 + strlen(de->d_name) + 1);
        strcpy(fullpath, path);
        if(path[npath - 1] != '/')
            strcat(fullpath, "/");
        strcat(fullpath, de->d_name);
        stat_impl(fullpath, hash_fn);
        free(fullpath);
    }

    closedir(dp);

    exit(0);
}

void do_tree(const char* path, const char* hash)
{
    hash_f_t hash_fn = (strcmp(hash, "crc32") == 0) ? crc32_hash : NULL;
    struct DirNode head = {
        .path = NULL,
        .next = NULL,
    };
    head.next = malloc(sizeof(struct DirNode));
    head.next->path = strdup(path);
    head.next->next = NULL;

    DIR* dp;
    struct dirent* de;

    while(head.next) {
        char* nextPath = head.next->path;
        struct DirNode* pOld = head.next;
        head.next = pOld->next;

        dp = opendir(nextPath);
        if(!dp) {
            warn("opendir %s", path);
            goto nextDe;
        }
        size_t npath = strlen(nextPath);

        while((de = readdir(dp)) != NULL) {
            if(strcmp(de->d_name, "..") == 0) continue;
            if(strcmp(de->d_name, ".") == 0) continue;
            // TODO have option to exclude dot files
            char* fullpath = malloc(npath + 1 + strlen(de->d_name) + 1);
            strcpy(fullpath, nextPath);
            if(nextPath[npath - 1] != '/')
                strcat(fullpath, "/");
            strcat(fullpath, de->d_name);
            // linux says de.d_type is unreliable, and we stat(2) the file anyway,
            // so stat_impl tells us if it's a directory or not
            STAT_RESULT iswhat = stat_impl(fullpath, hash_fn);
            if(iswhat == ISDIR) {
                // store the directory in the stack for later traversal
                struct DirNode* p = head.next;
                head.next = malloc(sizeof(struct DirNode));
                head.next->path = fullpath;
                head.next->next = p;
            } else {
                free(fullpath);
            }
        }

        closedir(dp);
nextDe:
        free(pOld);
        free(nextPath);
    }
    
    exit(0);
}

int main(int argc, char* argv[])
{
    if(argc <= 1
    || strcmp(argv[1], "help") == 0
    || strcmp(argv[1], "-h") == 0
    || strcmp(argv[1], "--help") == 0)
    {
        help(argv[0]);
    }

    if(strcmp(argv[1], "version") == 0
    || strcmp(argv[1], "-V") == 0
    || strcmp(argv[1], "--version") == 0)
    {
        printf("%s\n", VERSION);
        exit(0);
    }

    if(strcmp(argv[1], "ls") == 0 || strcmp(argv[1], "tree") == 0) {
        if(argc > 3 && strcmp(argv[3], "crc32")) {
            fprintf(stderr, "Unsupported hash %s\n", argv[3]);
            exit(2);
        }
        if(argc <= 2) {
            fprintf(stderr, "Missing path\n");
            exit(2);
        }
        void (*fp)(const char*, const char*) =
            (strcmp(argv[1], "ls") == 0)
            ? do_ls
            : do_tree;
        if(argc > 3) {
            fp(argv[2], argv[3]);
        } else {
            fp(argv[2], "");
        }
    } else if(strcmp(argv[1], "put") == 0 || strcmp(argv[1], "get") == 0) {
        if(argc <= 4) {
            fprintf(stderr, "Bad invocation\n");
            exit(2);
        }
        long start = atol(argv[2]);
        long end = atol(argv[3]);
        void (*fp)(const char*, long, long) =
            (strcmp(argv[1], "put") == 0)
            ? do_put
            : do_get;
        fp(argv[4], start, end);
    } else {
        fprintf(stderr, "%s is not an option\n", argv[1]);
        return 1;
    }

    return 0;
}
