// SPDX-License-Identifier: GPL-3.0-or-later
// A descriptor number may be reused by a child runtime. Test the inherited
// file's identity before opening the report, rather than echoing to that number.
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if (argc != 5) return 2;
    int descriptor = atoi(argv[1]);
    struct stat file;
    int inherited = fstat(descriptor, &file) == 0
        && (uint64_t)file.st_dev == strtoull(argv[3], NULL, 10)
        && (uint64_t)file.st_ino == strtoull(argv[4], NULL, 10);
    if (inherited && write(descriptor, "leaked", 6) != 6) return 3;
    int stdio = fcntl(0, F_GETFD) >= 0 && fcntl(1, F_GETFD) >= 0
        && fcntl(2, F_GETFD) >= 0 && write(1, "", 0) == 0;
    FILE *report = fopen(argv[2], "w");
    if (!report) return 4;
    fprintf(report, "%d %d", inherited, stdio);
    return fclose(report) == 0 ? 0 : 5;
}
