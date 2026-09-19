#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdint.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <ctype.h>

#define SFS_SECTOR_SIZE   512
#define SFS_NAME_LEN      11
#define SFS_FIRST_DATA    3
#define SFS_MIN_SIZE      (SFS_FIRST_DATA * SFS_SECTOR_SIZE)
#define SFS_DEFAULT_SIZE  (1024 * 1024)

static void put_u16(uint8_t *p, uint16_t v)
{
    p[0] = (uint8_t)(v & 0xff);
    p[1] = (uint8_t)((v >> 8) & 0xff);
}

static uint64_t parse_size(const char *s)
{
    char *end = NULL;
    unsigned long long n = strtoull(s, &end, 0);
    if (end == s)
        return 0;
    uint64_t mul = 1;
    switch (toupper((unsigned char)*end)) {
    case 'G': mul = 1024ULL * 1024 * 1024; end++; break;
    case 'M': mul = 1024ULL * 1024; end++; break;
    case 'K': mul = 1024ULL; end++; break;
    default: break;
    }
    if (*end != '\0')
        return 0;
    return n * mul;
}

static int write_all(int fd, const void *buf, size_t len, off_t off)
{
    const uint8_t *p = buf;
    while (len > 0) {
        ssize_t w = pwrite(fd, p, len, off);
        if (w < 0)
            return -1;
        p += (size_t)w;
        off += (off_t)w;
        len -= (size_t)w;
    }
    return 0;
}

static int zero_all(int fd, uint64_t size)
{
    static const uint8_t zero[SFS_SECTOR_SIZE] = {0};
    uint64_t off = 0;
    while (off < size) {
        size_t part = SFS_SECTOR_SIZE;
        if ((uint64_t)part > size - off)
            part = (size_t)(size - off);
        if (write_all(fd, zero, part, (off_t)off) < 0)
            return -1;
        off += part;
    }
    return 0;
}

static void usage(const char *prog)
{
    fprintf(stderr,
        "Usage: %s [options] <image> [size]\n"
        "Create an empty SFS filesystem image.\n"
        "\n"
        "  size       image size: <n> bytes or with suffix K/M/G (e.g. 1M).\n"
        "             If omitted, keeps the existing size; new images get 1M.\n"
        "  -b <file>  copy <file> into the boot sector (sector 0)\n"
        "  -p <name>  set the start program name (up to %d chars)\n",
        prog, SFS_NAME_LEN);
}

int main(int argc, char **argv)
{
    const char *image = NULL;
    const char *boot = NULL;
    const char *start_prog = "";
    const char *size_str = NULL;
    int have_size = 0;

    for (int i = 1; i < argc; i++) {
        const char *a = argv[i];
        if (strcmp(a, "-b") == 0 && i + 1 < argc) {
            boot = argv[++i];
        } else if (strcmp(a, "-p") == 0 && i + 1 < argc) {
            start_prog = argv[++i];
        } else if (strcmp(a, "-h") == 0 || strcmp(a, "--help") == 0) {
            usage(argv[0]);
            return 0;
        } else if (a[0] == '-' && strlen(a) > 1) {
            usage(argv[0]);
            return 2;
        } else if (image == NULL) {
            image = a;
        } else if (!have_size) {
            size_str = a;
            have_size = 1;
        } else {
            usage(argv[0]);
            return 2;
        }
    }

    if (image == NULL) {
        usage(argv[0]);
        return 2;
    }

    size_t plen = strlen(start_prog);
    if (plen > SFS_NAME_LEN) {
        fprintf(stderr, "mkfs.sfs: start program name too long (max %d chars)\n",
                SFS_NAME_LEN);
        return 1;
    }

    uint64_t size = 0;
    int need_create = 0;

    if (have_size) {
        size = parse_size(size_str);
        if (size == 0) {
            fprintf(stderr, "mkfs.sfs: invalid size '%s'\n", size_str);
            return 1;
        }
    }

    int fd = open(image, O_RDWR);
    if (fd < 0) {
        if (errno == ENOENT) {
            need_create = 1;
            fd = open(image, O_RDWR | O_CREAT, 0644);
        }
        if (fd < 0) {
            fprintf(stderr, "mkfs.sfs: cannot open %s: %s\n", image, strerror(errno));
            return 1;
        }
    }

    struct stat sb;
    if (fstat(fd, &sb) < 0) {
        fprintf(stderr, "mkfs.sfs: cannot stat %s: %s\n", image, strerror(errno));
        close(fd);
        return 1;
    }

    if (!need_create && !S_ISREG(sb.st_mode)) {
        fprintf(stderr, "mkfs.sfs: %s is not a regular file\n", image);
        close(fd);
        return 1;
    }

    if (!have_size) {
        if (need_create || sb.st_size == 0)
            size = SFS_DEFAULT_SIZE;
        else
            size = (uint64_t)sb.st_size;
    }

    if (size < SFS_MIN_SIZE) {
        fprintf(stderr, "mkfs.sfs: %s too small for an SFS image (need at least %d bytes)\n",
                image, SFS_MIN_SIZE);
        close(fd);
        return 1;
    }

    printf("mkfs.sfs: creating SFS image %s, %llu bytes\n",
           image, (unsigned long long)size);

    if (ftruncate(fd, (off_t)size) < 0) {
        fprintf(stderr, "mkfs.sfs: cannot resize %s: %s\n", image, strerror(errno));
        close(fd);
        return 1;
    }

    if (zero_all(fd, size) < 0) {
        fprintf(stderr, "mkfs.sfs: cannot write %s: %s\n", image, strerror(errno));
        close(fd);
        return 1;
    }

    uint8_t boot_sector[SFS_SECTOR_SIZE] = {0};
    if (boot) {
        int bfd = open(boot, O_RDONLY);
        if (bfd < 0) {
            fprintf(stderr, "mkfs.sfs: cannot open boot file %s: %s\n", boot, strerror(errno));
            close(fd);
            return 1;
        }
        ssize_t n = read(bfd, boot_sector, sizeof(boot_sector));
        if (n < 0) {
            fprintf(stderr, "mkfs.sfs: cannot read boot file %s: %s\n", boot, strerror(errno));
            close(bfd);
            close(fd);
            return 1;
        }
        close(bfd);
    }

    uint8_t sfsdd[SFS_SECTOR_SIZE] = {0};
    uint8_t empty_fht[SFS_SECTOR_SIZE] = {0};
    put_u16(sfsdd, SFS_FIRST_DATA);
    memcpy(sfsdd + 2, start_prog, plen);

    if (write_all(fd, boot_sector, sizeof(boot_sector), 0) < 0 ||
        write_all(fd, sfsdd, sizeof(sfsdd), (off_t)SFS_SECTOR_SIZE) < 0 ||
        write_all(fd, empty_fht, sizeof(empty_fht), (off_t)2 * SFS_SECTOR_SIZE) < 0) {
        fprintf(stderr, "mkfs.sfs: cannot write %s: %s\n", image, strerror(errno));
        close(fd);
        return 1;
    }

    if (fsync(fd) < 0) {
        fprintf(stderr, "mkfs.sfs: fsync failed on %s: %s\n", image, strerror(errno));
        close(fd);
        return 1;
    }
    close(fd);

    printf("mkfs.sfs: done\n");
    if (start_prog[0])
        printf("mkfs.sfs: start program: %s\n", start_prog);
    return 0;
}