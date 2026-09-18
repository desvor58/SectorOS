#define _GNU_SOURCE
#define FUSE_USE_VERSION 31

#include <fuse3/fuse.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdint.h>
#include <pthread.h>
#include <sys/stat.h>
#include <sys/statvfs.h>
#include <sys/types.h>
#include <limits.h>

#define SFS_SECTOR_SIZE   512
#define SFS_NAME_LEN      11
#define SFS_ENTRY_SIZE    16
#define SFS_ENTRIES       (SFS_SECTOR_SIZE / SFS_ENTRY_SIZE)
#define SFS_MAX_USED      (SFS_ENTRIES - 1)
#define SFS_ROOT_FHT      2
#define SFS_FIRST_DATA    3
#define SFS_MAX_DEPTH     128

#define SFS_TYPE_FILE     'F'
#define SFS_TYPE_EXEC     'E'
#define SFS_TYPE_DIR      'D'

struct sfs_entry {
    uint8_t  name[SFS_NAME_LEN];
    uint8_t  type;
    uint16_t data_start;
    uint16_t data_size;
} __attribute__((packed));

_Static_assert(sizeof(struct sfs_entry) == SFS_ENTRY_SIZE, "SFS entry must be 16 bytes");

struct sfs_level {
    struct sfs_entry ent;
    uint32_t dir_sec;
    int      idx;
};

struct sfs_resolved {
    struct sfs_entry ent;
    uint32_t dir_sec;
    int      idx;
    int      is_root;
};

static int               img_fd = -1;
static uint64_t          img_size;
static uint8_t           sfsdd_buf[SFS_SECTOR_SIZE];
static uint16_t          next_free_sec;
static uint32_t          sfs_map_bits;
static unsigned char    *sfs_used;
static time_t            mount_time;
static pthread_mutex_t   sfs_lock = PTHREAD_MUTEX_INITIALIZER;

static uint16_t sfs_get_u16(const uint8_t *p)
{
    return (uint16_t)(p[0] | (p[1] << 8));
}

static void sfs_put_u16(uint8_t *p, uint16_t v)
{
    p[0] = (uint8_t)(v & 0xff);
    p[1] = (uint8_t)((v >> 8) & 0xff);
}

static int sfs_touch(off_t offset, size_t len)
{
    uint64_t end = (uint64_t)offset + len;
    if (end > img_size)
        img_size = end;
    return 0;
}

static int sfs_read_sec(uint32_t sec, void *buf)
{
    ssize_t n = pread(img_fd, buf, SFS_SECTOR_SIZE, (off_t)sec * SFS_SECTOR_SIZE);
    if (n < 0)
        return -errno;
    if ((size_t)n < SFS_SECTOR_SIZE)
        memset((uint8_t *)buf + n, 0, SFS_SECTOR_SIZE - (size_t)n);
    return 0;
}

static int sfs_write_sec(uint32_t sec, const void *buf)
{
    ssize_t n = pwrite(img_fd, buf, SFS_SECTOR_SIZE, (off_t)sec * SFS_SECTOR_SIZE);
    if (n != (ssize_t)SFS_SECTOR_SIZE)
        return (n < 0) ? -errno : -EIO;
    sfs_touch((off_t)sec * SFS_SECTOR_SIZE, SFS_SECTOR_SIZE);
    return 0;
}

static int sfs_zero_range(off_t off, size_t len)
{
    static const uint8_t zero[SFS_SECTOR_SIZE] = {0};
    while (len > 0) {
        size_t part = (size_t)(SFS_SECTOR_SIZE - ((size_t)off % SFS_SECTOR_SIZE));
        if (part > len)
            part = len;
        ssize_t n = pwrite(img_fd, zero, part, off);
        if ((size_t)n != part)
            return (n < 0) ? -errno : -EIO;
        sfs_touch(off, part);
        off += (off_t)part;
        len -= part;
    }
    return 0;
}

static int sfs_zero_sectors(uint32_t sec, unsigned count)
{
    static const uint8_t zero[SFS_SECTOR_SIZE] = {0};
    for (unsigned i = 0; i < count; i++) {
        int rc = sfs_write_sec(sec + i, zero);
        if (rc)
            return rc;
    }
    return 0;
}

static int sfsdd_load(void)
{
    int rc = sfs_read_sec(1, sfsdd_buf);
    if (rc)
        return rc;
    next_free_sec = sfs_get_u16(sfsdd_buf);
    return 0;
}

static int sfsdd_save(void)
{
    sfs_put_u16(sfsdd_buf, next_free_sec);
    return sfs_write_sec(1, sfsdd_buf);
}

static uint32_t sfs_ext_for(uint32_t size)
{
    uint32_t e = (size + SFS_SECTOR_SIZE - 1) / SFS_SECTOR_SIZE;
    if (e == 0)
        e = 1;
    return e;
}

static int sfs_map_reserve(uint32_t bits)
{
    if (bits <= sfs_map_bits)
        return 0;
    unsigned char *np = realloc(sfs_used, (bits + 7) / 8);
    if (!np)
        return -ENOMEM;
    memset(np + (sfs_map_bits + 7) / 8, 0,
           (bits + 7) / 8 - (sfs_map_bits + 7) / 8);
    sfs_used = np;
    sfs_map_bits = bits;
    return 0;
}

static int sec_used(uint32_t s)
{
    return (sfs_used[s >> 3] >> (s & 7)) & 1;
}

static void sec_set(uint32_t s)
{
    sfs_used[s >> 3] |= (unsigned char)(1 << (s & 7));
}

static void sec_clear(uint32_t s)
{
    sfs_used[s >> 3] &= (unsigned char)~(1 << (s & 7));
}

static void sfs_map_mark(uint32_t start, unsigned count)
{
    for (unsigned i = 0; i < count; i++)
        sec_set(start + i);
    uint32_t v = start + count;
    if (v > 0xFFFF)
        v = 0xFFFF;
    if (v > next_free_sec)
        next_free_sec = (uint16_t)v;
}

static void sfs_map_clamp_watermark(void)
{
    while (next_free_sec > 3 && !sec_used(next_free_sec - 1))
        next_free_sec--;
}

static int sfs_alloc_sectors(uint32_t *out, unsigned count)
{
    if (count == 0) {
        *out = 0;
        return 0;
    }

    for (uint32_t s = SFS_FIRST_DATA; s + count <= next_free_sec;) {
        if (sec_used(s)) {
            s++;
            continue;
        }
        uint32_t run = 0;
        while (run < count && !sec_used(s + run))
            run++;
        if (run == count) {
            sfs_map_mark(s, count);
            sfsdd_save();
            *out = s;
            return 0;
        }
        s += run + 1;
    }

    if ((uint32_t)next_free_sec + count > 0xFFFF)
        return -ENOSPC;
    if (sfs_map_reserve((uint32_t)next_free_sec + count) < 0)
        return -ENOMEM;
    uint32_t s = next_free_sec;
    sfs_map_mark(s, count);
    sfsdd_save();
    *out = s;
    return 0;
}

static void sfs_free_sectors(uint32_t start, unsigned count)
{
    for (unsigned i = 0; i < count; i++)
        sec_clear(start + i);
    sfs_map_clamp_watermark();
    sfsdd_save();
}

static int sfs_map_scan_dir(uint32_t dir_sec, int depth)
{
    if (depth > SFS_MAX_DEPTH)
        return 0;
    if (dir_sec < 2)
        return 0;
    if (sfs_map_reserve(dir_sec + 1) < 0)
        return 0;
    if (sec_used(dir_sec))
        return 0;

    uint8_t fht[SFS_SECTOR_SIZE];
    int rc = sfs_read_sec(dir_sec, fht);
    if (rc)
        return 0;

    sec_set(dir_sec);
    if (dir_sec + 1 > next_free_sec)
        next_free_sec = (uint16_t)(dir_sec + 1);

    for (int i = 0; i < SFS_ENTRIES; i++) {
        const struct sfs_entry *e = (const struct sfs_entry *)(fht + i * SFS_ENTRY_SIZE);
        if (e->name[0] == 0)
            break;
        if (e->data_start < SFS_FIRST_DATA)
            continue;

        if (e->type == SFS_TYPE_DIR) {
            sfs_map_scan_dir((uint32_t)e->data_start, depth + 1);
        } else {
            unsigned ext = sfs_ext_for(e->data_size);
            if (sfs_map_reserve((uint32_t)e->data_start + ext) < 0)
                continue;
            for (unsigned j = 0; j < ext; j++) {
                uint32_t s = (uint32_t)e->data_start + j;
                if (!sec_used(s))
                    sec_set(s);
            }
            if ((uint32_t)e->data_start + ext > next_free_sec)
                next_free_sec = (uint16_t)((uint32_t)e->data_start + ext);
        }
    }
    return 0;
}

static int sfs_map_build(void)
{
    uint64_t total_sec = img_size / SFS_SECTOR_SIZE;
    if (total_sec < SFS_FIRST_DATA)
        total_sec = SFS_FIRST_DATA;
    int rc = sfs_map_reserve((uint32_t)total_sec);
    if (rc)
        return rc;

    sec_set(0);
    sec_set(1);
    next_free_sec = SFS_FIRST_DATA;

    sfs_map_scan_dir(SFS_ROOT_FHT, 0);
    if (next_free_sec < SFS_FIRST_DATA)
        next_free_sec = SFS_FIRST_DATA;
    return 0;
}

static int sfs_entry_matches(const struct sfs_entry *e, const char *name)
{
    size_t len = strlen(name);
    if (len > SFS_NAME_LEN)
        return 0;
    for (size_t i = 0; i < SFS_NAME_LEN; i++) {
        char c = (i < len) ? name[i] : '\0';
        if ((char)e->name[i] != c)
            return 0;
    }
    return 1;
}

static void sfs_entry_set_name(struct sfs_entry *e, const char *name)
{
    memset(e->name, 0, SFS_NAME_LEN);
    size_t len = strlen(name);
    if (len > SFS_NAME_LEN)
        len = SFS_NAME_LEN;
    memcpy(e->name, name, len);
}

static void sfs_entry_to_stat(const struct sfs_entry *e, struct stat *st)
{
    memset(st, 0, sizeof(*st));
    st->st_uid = getuid();
    st->st_gid = getgid();
    st->st_atime = st->st_mtime = st->st_ctime = mount_time;
    st->st_blksize = SFS_SECTOR_SIZE;

    if (e->type == SFS_TYPE_DIR) {
        st->st_mode = S_IFDIR | 0777;
        st->st_size = SFS_SECTOR_SIZE;
        st->st_nlink = 2;
    } else {
        st->st_mode = S_IFREG | 0777;
        st->st_size = e->data_size;
        st->st_nlink = 1;
    }
    st->st_blocks = (st->st_size + SFS_SECTOR_SIZE - 1) / SFS_SECTOR_SIZE;
    if (st->st_blocks == 0)
        st->st_blocks = 1;
}

static int sfs_find_in_dir(uint32_t dir_sec, const char *name,
                           struct sfs_entry *out, int *idx)
{
    uint8_t fht[SFS_SECTOR_SIZE];
    int rc = sfs_read_sec(dir_sec, fht);
    if (rc)
        return rc;

    for (int i = 0; i < SFS_ENTRIES; i++) {
        const struct sfs_entry *e = (const struct sfs_entry *)(fht + i * SFS_ENTRY_SIZE);
        if (e->name[0] == 0)
            return -ENOENT;
        if (sfs_entry_matches(e, name)) {
            if (out)
                *out = *e;
            if (idx)
                *idx = i;
            return 0;
        }
    }
    return -ENOENT;
}

static int sfs_find_free_slot(uint32_t dir_sec)
{
    uint8_t fht[SFS_SECTOR_SIZE];
    int rc = sfs_read_sec(dir_sec, fht);
    if (rc)
        return rc;
    for (int i = 0; i < SFS_ENTRIES; i++) {
        const struct sfs_entry *e = (const struct sfs_entry *)(fht + i * SFS_ENTRY_SIZE);
        if (e->name[0] == 0)
            return (i >= SFS_MAX_USED) ? -ENOSPC : i;
    }
    return -ENOSPC;
}

static int sfs_split_path(char *path, char **comps, int max)
{
    int n = 0;
    char *p = path;
    while (*p) {
        while (*p == '/')
            p++;
        if (!*p)
            break;
        if (n >= max)
            return -1;
        comps[n++] = p;
        while (*p && *p != '/')
            p++;
        if (*p)
            *p++ = '\0';
    }
    return n;
}

static int sfs_walk_levels(char **comps, int nc, struct sfs_level *stk, int *sp_out)
{
    if (nc >= SFS_MAX_DEPTH)
        return -ENAMETOOLONG;

    stk[0].ent.type = SFS_TYPE_DIR;
    stk[0].ent.data_start = SFS_ROOT_FHT;
    stk[0].ent.data_size = SFS_SECTOR_SIZE;
    stk[0].dir_sec = SFS_ROOT_FHT;
    stk[0].idx = -1;
    int sp = 1;

    for (int j = 0; j < nc; j++) {
        const char *c = comps[j];
        int is_last = (j == nc - 1);

        if (c[0] == '\0')
            continue;
        if (strcmp(c, ".") == 0)
            continue;
        if (strcmp(c, "..") == 0) {
            if (sp > 1)
                sp--;
            continue;
        }

        struct sfs_level *top = &stk[sp - 1];
        if (top->ent.type != SFS_TYPE_DIR)
            return -ENOTDIR;

        uint32_t cur_sec = top->ent.data_start;
        struct sfs_entry e;
        int idx;
        int rc = sfs_find_in_dir(cur_sec, c, &e, &idx);
        if (rc)
            return rc;

        if (!is_last && e.type != SFS_TYPE_DIR)
            return -ENOTDIR;
        if (sp >= SFS_MAX_DEPTH)
            return -ENAMETOOLONG;

        stk[sp].ent = e;
        stk[sp].dir_sec = cur_sec;
        stk[sp].idx = idx;
        sp++;
    }

    *sp_out = sp;
    return 0;
}

static int sfs_resolve(const char *path, struct sfs_resolved *out)
{
    char *comps[SFS_MAX_DEPTH];
    char tmp[PATH_MAX];
    size_t plen = strlen(path);
    if (plen >= sizeof(tmp))
        return -ENAMETOOLONG;
    memcpy(tmp, path, plen + 1);

    int nc = sfs_split_path(tmp, comps, SFS_MAX_DEPTH);
    if (nc < 0)
        return -ENAMETOOLONG;

    struct sfs_level stk[SFS_MAX_DEPTH];
    int sp;
    int rc = sfs_walk_levels(comps, nc, stk, &sp);
    if (rc)
        return rc;

    const struct sfs_level *top = &stk[sp - 1];
    out->ent = top->ent;
    out->dir_sec = top->dir_sec;
    out->idx = top->idx;
    out->is_root = (sp == 1);
    return 0;
}

static int sfs_resolve_parent(const char *path, char *name_out, size_t name_cap,
                              uint32_t *parent_sec_out)
{
    char *comps[SFS_MAX_DEPTH];
    char tmp[PATH_MAX];
    size_t plen = strlen(path);
    if (plen >= sizeof(tmp))
        return -ENAMETOOLONG;
    memcpy(tmp, path, plen + 1);

    int nc = sfs_split_path(tmp, comps, SFS_MAX_DEPTH);
    if (nc < 0)
        return -ENAMETOOLONG;
    if (nc == 0)
        return -ENOENT;

    const char *name = comps[nc - 1];
    size_t nlen = strlen(name);
    if (nlen == 0)
        return -ENOENT;
    if (nlen > SFS_NAME_LEN)
        return -ENAMETOOLONG;

    struct sfs_level stk[SFS_MAX_DEPTH];
    int sp;
    int rc = sfs_walk_levels(comps, nc - 1, stk, &sp);
    if (rc)
        return rc;

    const struct sfs_level *top = &stk[sp - 1];
    if (top->ent.type != SFS_TYPE_DIR)
        return -ENOTDIR;

    size_t copy = nlen;
    if (copy >= name_cap)
        copy = name_cap - 1;
    memcpy(name_out, name, copy);
    name_out[copy] = '\0';

    *parent_sec_out = top->ent.data_start;
    return 0;
}

static int sfs_write_entry(uint32_t dir_sec, int idx, const struct sfs_entry *e)
{
    uint8_t fht[SFS_SECTOR_SIZE];
    int rc = sfs_read_sec(dir_sec, fht);
    if (rc)
        return rc;
    if (idx < 0 || idx >= SFS_ENTRIES)
        return -EINVAL;
    memcpy(fht + idx * SFS_ENTRY_SIZE, e, SFS_ENTRY_SIZE);
    return sfs_write_sec(dir_sec, fht);
}

static int sfs_remove_entry(uint32_t dir_sec, int idx)
{
    uint8_t fht[SFS_SECTOR_SIZE];
    int rc = sfs_read_sec(dir_sec, fht);
    if (rc)
        return rc;
    if (idx < 0 || idx >= SFS_ENTRIES)
        return -EINVAL;

    int e = idx;
    while (e < SFS_ENTRIES && ((struct sfs_entry *)(fht + e * SFS_ENTRY_SIZE))->name[0] != 0)
        e++;

    for (int i = idx + 1; i < e; i++)
        memcpy(fht + (i - 1) * SFS_ENTRY_SIZE, fht + i * SFS_ENTRY_SIZE, SFS_ENTRY_SIZE);
    memset(fht + (e - 1) * SFS_ENTRY_SIZE, 0, SFS_ENTRY_SIZE);

    return sfs_write_sec(dir_sec, fht);
}

static int sfs_copy_data(uint32_t src_sec, uint32_t dst_sec, size_t bytes)
{
    size_t done = 0;
    uint8_t buf[65336];
    while (done < bytes) {
        size_t chunk = bytes - done;
        if (chunk > sizeof(buf))
            chunk = sizeof(buf);
        ssize_t r = pread(img_fd, buf, chunk, (off_t)src_sec * SFS_SECTOR_SIZE + (off_t)done);
        if (r <= 0)
            return (r < 0) ? -errno : -EIO;
        ssize_t w = pwrite(img_fd, buf, (size_t)r, (off_t)dst_sec * SFS_SECTOR_SIZE + (off_t)done);
        if (w != r)
            return (w < 0) ? -errno : -EIO;
        sfs_touch((off_t)dst_sec * SFS_SECTOR_SIZE + (off_t)done, (size_t)r);
        done += (size_t)r;
    }
    return 0;
}

static int sfs_prepare_block(const struct sfs_resolved *r, off_t new_size,
                             uint32_t *start_out, int *changed_out)
{
    uint32_t cur_ext = sfs_ext_for(r->ent.data_size);
    uint32_t need_ext = sfs_ext_for((uint32_t)new_size);
    uint32_t start = r->ent.data_start;

    *start_out = start;
    *changed_out = 0;

    if (need_ext == cur_ext)
        return 0;

    uint32_t new_start = 0;
    int rc = sfs_alloc_sectors(&new_start, need_ext);
    if (rc)
        return rc;
    rc = sfs_zero_sectors(new_start, need_ext);
    if (rc) {
        sfs_free_sectors(new_start, need_ext);
        return rc;
    }
    if (r->ent.data_size > 0) {
        rc = sfs_copy_data(start, new_start, r->ent.data_size);
        if (rc) {
            sfs_free_sectors(new_start, need_ext);
            return rc;
        }
    }

    sfs_free_sectors(start, cur_ext);

    *start_out = new_start;
    *changed_out = 1;
    return 0;
}

static int sfs_getattr(const char *path, struct stat *st, struct fuse_file_info *fi)
{
    (void)fi;
    pthread_mutex_lock(&sfs_lock);
    struct sfs_resolved r;
    int rc = sfs_resolve(path, &r);
    if (rc) {
        pthread_mutex_unlock(&sfs_lock);
        return rc;
    }
    sfs_entry_to_stat(&r.ent, st);
    pthread_mutex_unlock(&sfs_lock);
    return 0;
}

static int sfs_readdir(const char *path, void *buf, fuse_fill_dir_t filler,
                       off_t offset, struct fuse_file_info *fi,
                       enum fuse_readdir_flags flags)
{
    (void)offset;
    (void)fi;
    (void)flags;

    pthread_mutex_lock(&sfs_lock);
    struct sfs_resolved r;
    int rc = sfs_resolve(path, &r);
    if (rc) {
        pthread_mutex_unlock(&sfs_lock);
        return rc;
    }
    if (r.ent.type != SFS_TYPE_DIR) {
        pthread_mutex_unlock(&sfs_lock);
        return -ENOTDIR;
    }

    filler(buf, ".", NULL, 0, 0);
    filler(buf, "..", NULL, 0, 0);

    uint8_t fht[SFS_SECTOR_SIZE];
    rc = sfs_read_sec(r.ent.data_start, fht);
    if (!rc) {
        for (int i = 0; i < SFS_ENTRIES; i++) {
            const struct sfs_entry *e = (const struct sfs_entry *)(fht + i * SFS_ENTRY_SIZE);
            if (e->name[0] == 0)
                break;
            char nm[SFS_NAME_LEN + 1];
            memcpy(nm, e->name, SFS_NAME_LEN);
            nm[SFS_NAME_LEN] = '\0';
            struct stat st;
            sfs_entry_to_stat(e, &st);
            if (filler(buf, nm, &st, 0, 0))
                break;
        }
    }

    pthread_mutex_unlock(&sfs_lock);
    return 0;
}

static int sfs_open(const char *path, struct fuse_file_info *fi)
{
    (void)fi;
    pthread_mutex_lock(&sfs_lock);
    struct sfs_resolved r;
    int rc = sfs_resolve(path, &r);
    if (rc) {
        pthread_mutex_unlock(&sfs_lock);
        return rc;
    }
    if (r.ent.type == SFS_TYPE_DIR) {
        pthread_mutex_unlock(&sfs_lock);
        return -EISDIR;
    }
    pthread_mutex_unlock(&sfs_lock);
    return 0;
}

static int sfs_read(const char *path, char *buf, size_t size, off_t offset,
                    struct fuse_file_info *fi)
{
    (void)fi;
    pthread_mutex_lock(&sfs_lock);
    struct sfs_resolved r;
    int rc = sfs_resolve(path, &r);
    if (rc) {
        pthread_mutex_unlock(&sfs_lock);
        return rc;
    }
    if (r.ent.type == SFS_TYPE_DIR) {
        pthread_mutex_unlock(&sfs_lock);
        return -EISDIR;
    }

    off_t fsize = (off_t)r.ent.data_size;
    if (offset >= fsize) {
        pthread_mutex_unlock(&sfs_lock);
        return 0;
    }
    if ((off_t)size > fsize - offset)
        size = (size_t)(fsize - offset);

    if (r.ent.data_start < SFS_FIRST_DATA) {
        pthread_mutex_unlock(&sfs_lock);
        return -EIO;
    }

    off_t img_off = (off_t)r.ent.data_start * SFS_SECTOR_SIZE + offset;
    ssize_t n = pread(img_fd, buf, size, img_off);
    pthread_mutex_unlock(&sfs_lock);
    if (n < 0)
        return -errno;
    return (int)n;
}

static int sfs_write(const char *path, const char *buf, size_t size, off_t offset,
                     struct fuse_file_info *fi)
{
    (void)fi;
    pthread_mutex_lock(&sfs_lock);
    struct sfs_resolved r;
    int rc = sfs_resolve(path, &r);
    if (rc) {
        pthread_mutex_unlock(&sfs_lock);
        return rc;
    }
    if (r.ent.type == SFS_TYPE_DIR) {
        pthread_mutex_unlock(&sfs_lock);
        return -EISDIR;
    }

    uint16_t old_size = r.ent.data_size;

    off_t new_size = (off_t)old_size;
    if ((off_t)offset + (off_t)size > new_size)
        new_size = (off_t)offset + (off_t)size;
    if (new_size > 0xFFFF) {
        pthread_mutex_unlock(&sfs_lock);
        return -EFBIG;
    }

    uint32_t start;
    int changed;
    rc = sfs_prepare_block(&r, new_size, &start, &changed);
    if (rc) {
        pthread_mutex_unlock(&sfs_lock);
        return rc;
    }

    if (offset > (off_t)old_size) {
        rc = sfs_zero_range((off_t)start * SFS_SECTOR_SIZE + old_size,
                            (size_t)(offset - old_size));
        if (rc) {
            pthread_mutex_unlock(&sfs_lock);
            return rc;
        }
    }

    ssize_t n = pwrite(img_fd, buf, size,
                       (off_t)start * SFS_SECTOR_SIZE + offset);
    if (n < 0) {
        pthread_mutex_unlock(&sfs_lock);
        return -errno;
    }
    sfs_touch((off_t)start * SFS_SECTOR_SIZE + offset, (size_t)n);

    struct sfs_entry ne = r.ent;
    if (changed)
        ne.data_start = (uint16_t)start;
    ne.data_size = (uint16_t)new_size;
    rc = sfs_write_entry(r.dir_sec, r.idx, &ne);
    pthread_mutex_unlock(&sfs_lock);
    if (rc)
        return rc;
    return (int)n;
}

static int sfs_truncate(const char *path, off_t size, struct fuse_file_info *fi)
{
    (void)fi;
    if (size < 0)
        size = 0;
    if (size > 0xFFFF)
        return -EFBIG;

    pthread_mutex_lock(&sfs_lock);
    struct sfs_resolved r;
    int rc = sfs_resolve(path, &r);
    if (rc) {
        pthread_mutex_unlock(&sfs_lock);
        return rc;
    }
    if (r.ent.type == SFS_TYPE_DIR) {
        pthread_mutex_unlock(&sfs_lock);
        return -EISDIR;
    }

    uint16_t old_size = r.ent.data_size;
    if (size == (off_t)old_size) {
        pthread_mutex_unlock(&sfs_lock);
        return 0;
    }

    uint32_t start;
    int changed;
    rc = sfs_prepare_block(&r, size, &start, &changed);
    if (rc) {
        pthread_mutex_unlock(&sfs_lock);
        return rc;
    }

    if (size > (off_t)old_size) {
        rc = sfs_zero_range((off_t)start * SFS_SECTOR_SIZE + old_size,
                            (size_t)(size - old_size));
        if (rc) {
            pthread_mutex_unlock(&sfs_lock);
            return rc;
        }
    }

    struct sfs_entry ne = r.ent;
    if (changed)
        ne.data_start = (uint16_t)start;
    ne.data_size = (uint16_t)size;
    rc = sfs_write_entry(r.dir_sec, r.idx, &ne);
    pthread_mutex_unlock(&sfs_lock);
    return rc;
}

static int sfs_make_file(const char *path, mode_t mode)
{
    char name[SFS_NAME_LEN + 1];
    uint32_t parent_sec;
    int rc = sfs_resolve_parent(path, name, sizeof(name), &parent_sec);
    if (rc)
        return rc;

    struct sfs_entry e;
    int idx;
    rc = sfs_find_in_dir(parent_sec, name, &e, &idx);
    if (rc == 0)
        return -EEXIST;
    if (rc != -ENOENT)
        return rc;

    int slot = sfs_find_free_slot(parent_sec);
    if (slot < 0)
        return slot;

    uint32_t sec;
    rc = sfs_alloc_sectors(&sec, 1);
    if (rc)
        return rc;

    memset(&e, 0, sizeof(e));
    sfs_entry_set_name(&e, name);
    e.type = (mode & 0111) ? SFS_TYPE_EXEC : SFS_TYPE_FILE;
    e.data_start = (uint16_t)sec;
    e.data_size = 0;
    return sfs_write_entry(parent_sec, slot, &e);
}

static int sfs_create(const char *path, mode_t mode, struct fuse_file_info *fi)
{
    (void)fi;
    pthread_mutex_lock(&sfs_lock);
    int rc = sfs_make_file(path, mode);
    pthread_mutex_unlock(&sfs_lock);
    return rc;
}

static int sfs_mknod(const char *path, mode_t mode, dev_t rdev)
{
    (void)rdev;
    if (!S_ISREG(mode))
        return -EPERM;
    pthread_mutex_lock(&sfs_lock);
    int rc = sfs_make_file(path, mode);
    pthread_mutex_unlock(&sfs_lock);
    return rc;
}

static int sfs_mkdir(const char *path, mode_t mode)
{
    (void)mode;
    pthread_mutex_lock(&sfs_lock);

    char name[SFS_NAME_LEN + 1];
    uint32_t parent_sec;
    int rc = sfs_resolve_parent(path, name, sizeof(name), &parent_sec);
    if (rc) {
        pthread_mutex_unlock(&sfs_lock);
        return rc;
    }

    struct sfs_entry e;
    int idx;
    rc = sfs_find_in_dir(parent_sec, name, &e, &idx);
    if (rc == 0) {
        pthread_mutex_unlock(&sfs_lock);
        return -EEXIST;
    }
    if (rc != -ENOENT) {
        pthread_mutex_unlock(&sfs_lock);
        return rc;
    }

    int slot = sfs_find_free_slot(parent_sec);
    if (slot < 0) {
        pthread_mutex_unlock(&sfs_lock);
        return slot;
    }

    uint32_t table_sec;
    rc = sfs_alloc_sectors(&table_sec, 1);
    if (rc) {
        pthread_mutex_unlock(&sfs_lock);
        return rc;
    }
    rc = sfs_zero_sectors(table_sec, 1);
    if (rc) {
        pthread_mutex_unlock(&sfs_lock);
        return rc;
    }

    memset(&e, 0, sizeof(e));
    sfs_entry_set_name(&e, name);
    e.type = SFS_TYPE_DIR;
    e.data_start = (uint16_t)table_sec;
    e.data_size = SFS_SECTOR_SIZE;
    rc = sfs_write_entry(parent_sec, slot, &e);

    pthread_mutex_unlock(&sfs_lock);
    return rc;
}

static int sfs_unlink(const char *path)
{
    pthread_mutex_lock(&sfs_lock);
    struct sfs_resolved r;
    int rc = sfs_resolve(path, &r);
    if (rc) {
        pthread_mutex_unlock(&sfs_lock);
        return rc;
    }
    if (r.is_root) {
        pthread_mutex_unlock(&sfs_lock);
        return -EBUSY;
    }
    if (r.ent.type == SFS_TYPE_DIR) {
        pthread_mutex_unlock(&sfs_lock);
        return -EISDIR;
    }
    rc = sfs_remove_entry(r.dir_sec, r.idx);
    if (!rc)
        sfs_free_sectors(r.ent.data_start, sfs_ext_for(r.ent.data_size));
    pthread_mutex_unlock(&sfs_lock);
    return rc;
}

static int sfs_rmdir(const char *path)
{
    pthread_mutex_lock(&sfs_lock);
    struct sfs_resolved r;
    int rc = sfs_resolve(path, &r);
    if (rc) {
        pthread_mutex_unlock(&sfs_lock);
        return rc;
    }
    if (r.is_root) {
        pthread_mutex_unlock(&sfs_lock);
        return -EBUSY;
    }
    if (r.ent.type != SFS_TYPE_DIR) {
        pthread_mutex_unlock(&sfs_lock);
        return -ENOTDIR;
    }

    uint8_t fht[SFS_SECTOR_SIZE];
    rc = sfs_read_sec(r.ent.data_start, fht);
    if (rc) {
        pthread_mutex_unlock(&sfs_lock);
        return rc;
    }
    for (int i = 0; i < SFS_ENTRIES; i++) {
        const struct sfs_entry *e = (const struct sfs_entry *)(fht + i * SFS_ENTRY_SIZE);
        if (e->name[0] == 0)
            break;
        pthread_mutex_unlock(&sfs_lock);
        return -ENOTEMPTY;
    }

    rc = sfs_remove_entry(r.dir_sec, r.idx);
    if (!rc)
        sfs_free_sectors(r.ent.data_start, 1);
    pthread_mutex_unlock(&sfs_lock);
    return rc;
}

static int sfs_rename(const char *oldpath, const char *newpath, unsigned int flags)
{
    if (flags & (RENAME_EXCHANGE | RENAME_NOREPLACE))
        return -EINVAL;

    pthread_mutex_lock(&sfs_lock);

    struct sfs_resolved src;
    int rc = sfs_resolve(oldpath, &src);
    if (rc) {
        pthread_mutex_unlock(&sfs_lock);
        return rc;
    }
    if (src.is_root) {
        pthread_mutex_unlock(&sfs_lock);
        return -EBUSY;
    }

    if (src.ent.type == SFS_TYPE_DIR) {
        size_t olen = strlen(oldpath);
        size_t nlen = strlen(newpath);
        if (nlen > olen &&
            memcmp(oldpath, newpath, olen) == 0 &&
            (newpath[olen] == '/' || newpath[olen] == '\0')) {
            pthread_mutex_unlock(&sfs_lock);
            return -EINVAL;
        }
    }

    char name[SFS_NAME_LEN + 1];
    uint32_t dst_sec;
    rc = sfs_resolve_parent(newpath, name, sizeof(name), &dst_sec);
    if (rc) {
        pthread_mutex_unlock(&sfs_lock);
        return rc;
    }

    if (dst_sec == src.dir_sec) {
        struct sfs_entry probe;
        int probe_idx;
        rc = sfs_find_in_dir(dst_sec, name, &probe, &probe_idx);
        if (rc == 0 && probe_idx != src.idx) {
            pthread_mutex_unlock(&sfs_lock);
            return -EEXIST;
        }
        if (rc != 0 && rc != -ENOENT) {
            pthread_mutex_unlock(&sfs_lock);
            return rc;
        }

        uint8_t fht[SFS_SECTOR_SIZE];
        rc = sfs_read_sec(dst_sec, fht);
        if (rc == 0) {
            struct sfs_entry *e = (struct sfs_entry *)(fht + src.idx * SFS_ENTRY_SIZE);
            sfs_entry_set_name(e, name);
            rc = sfs_write_sec(dst_sec, fht);
        }
        pthread_mutex_unlock(&sfs_lock);
        return rc;
    }

    struct sfs_entry probe;
    int probe_idx;
    rc = sfs_find_in_dir(dst_sec, name, &probe, &probe_idx);
    if (rc == 0) {
        pthread_mutex_unlock(&sfs_lock);
        return -EEXIST;
    }
    if (rc != -ENOENT) {
        pthread_mutex_unlock(&sfs_lock);
        return rc;
    }

    int slot = sfs_find_free_slot(dst_sec);
    if (slot < 0) {
        pthread_mutex_unlock(&sfs_lock);
        return slot;
    }

    struct sfs_entry ne = src.ent;
    sfs_entry_set_name(&ne, name);
    rc = sfs_write_entry(dst_sec, slot, &ne);
    if (rc) {
        pthread_mutex_unlock(&sfs_lock);
        return rc;
    }
    rc = sfs_remove_entry(src.dir_sec, src.idx);
    pthread_mutex_unlock(&sfs_lock);
    return rc;
}

static int sfs_chmod(const char *path, mode_t mode, struct fuse_file_info *fi)
{
    (void)fi;
    pthread_mutex_lock(&sfs_lock);
    struct sfs_resolved r;
    int rc = sfs_resolve(path, &r);
    if (rc) {
        pthread_mutex_unlock(&sfs_lock);
        return rc;
    }
    if (r.ent.type == SFS_TYPE_DIR) {
        pthread_mutex_unlock(&sfs_lock);
        return 0;
    }

    uint8_t want = (mode & 0111) ? SFS_TYPE_EXEC : SFS_TYPE_FILE;
    if (r.ent.type != want) {
        uint8_t fht[SFS_SECTOR_SIZE];
        rc = sfs_read_sec(r.dir_sec, fht);
        if (!rc) {
            fht[r.idx * SFS_ENTRY_SIZE + 11] = want;
            rc = sfs_write_sec(r.dir_sec, fht);
        }
    }
    pthread_mutex_unlock(&sfs_lock);
    return rc;
}

static int sfs_chown(const char *path, uid_t uid, gid_t gid, struct fuse_file_info *fi)
{
    (void)path;
    (void)uid;
    (void)gid;
    (void)fi;
    return 0;
}

static int sfs_truncate_file(const char *path, off_t size, struct fuse_file_info *fi)
{
    return sfs_truncate(path, size, fi);
}

static int sfs_statfs(const char *path, struct statvfs *st)
{
    (void)path;
    pthread_mutex_lock(&sfs_lock);
    memset(st, 0, sizeof(*st));
    st->f_bsize = SFS_SECTOR_SIZE;
    st->f_frsize = SFS_SECTOR_SIZE;
    uint64_t total = img_size / SFS_SECTOR_SIZE;
    if (total < next_free_sec)
        total = next_free_sec;
    st->f_blocks = total;
    uint64_t used = 0;
    for (uint32_t i = 0; i < sfs_map_bits; i++)
        if (sec_used(i))
            used++;
    uint64_t freev = (total > used) ? (total - used) : 0;
    st->f_bfree = freev;
    st->f_bavail = freev;
    st->f_files = 1024;
    st->f_ffree = 1020;
    st->f_namemax = SFS_NAME_LEN;
    pthread_mutex_unlock(&sfs_lock);
    return 0;
}

static int sfs_access(const char *path, int mask)
{
    (void)mask;
    pthread_mutex_lock(&sfs_lock);
    struct sfs_resolved r;
    int rc = sfs_resolve(path, &r);
    pthread_mutex_unlock(&sfs_lock);
    return rc;
}

static int sfs_utimens(const char *path, const struct timespec tv[2],
                       struct fuse_file_info *fi)
{
    (void)path;
    (void)tv;
    (void)fi;
    return 0;
}

static int sfs_opendir(const char *path, struct fuse_file_info *fi)
{
    (void)fi;
    pthread_mutex_lock(&sfs_lock);
    struct sfs_resolved r;
    int rc = sfs_resolve(path, &r);
    if (!rc && r.ent.type != SFS_TYPE_DIR)
        rc = -ENOTDIR;
    pthread_mutex_unlock(&sfs_lock);
    return rc;
}

static int sfs_fsync(const char *path, int datasync, struct fuse_file_info *fi)
{
    (void)path;
    (void)datasync;
    (void)fi;
    if (fsync(img_fd) < 0)
        return -errno;
    return 0;
}

static int sfs_release(const char *path, struct fuse_file_info *fi)
{
    (void)path;
    (void)fi;
    return 0;
}

static int sfs_flush(const char *path, struct fuse_file_info *fi)
{
    (void)path;
    (void)fi;
    return 0;
}

static void *sfs_init(struct fuse_conn_info *conn, struct fuse_config *cfg)
{
    (void)conn;
    cfg->kernel_cache = 0;
    cfg->attr_timeout = 0;
    cfg->entry_timeout = 0;
    cfg->negative_timeout = 0;
    return NULL;
}

static const struct fuse_operations sfs_ops = {
    .init     = sfs_init,
    .getattr  = sfs_getattr,
    .readlink = NULL,
    .mknod    = sfs_mknod,
    .mkdir    = sfs_mkdir,
    .unlink   = sfs_unlink,
    .rmdir    = sfs_rmdir,
    .symlink  = NULL,
    .rename   = sfs_rename,
    .link     = NULL,
    .chmod    = sfs_chmod,
    .chown    = sfs_chown,
    .truncate = sfs_truncate_file,
    .open     = sfs_open,
    .read     = sfs_read,
    .write    = sfs_write,
    .statfs   = sfs_statfs,
    .flush    = sfs_flush,
    .release  = sfs_release,
    .fsync    = sfs_fsync,
    .opendir  = sfs_opendir,
    .readdir  = sfs_readdir,
    .access   = sfs_access,
    .create   = sfs_create,
    .utimens  = sfs_utimens,
};

static void usage(const char *prog)
{
    fprintf(stderr, "Usage: %s <disk-image> <mountpoint> [fuse3 options]\n", prog);
    fprintf(stderr, "       e.g. %s disk.img /mnt/sos -f\n", prog);
}

int main(int argc, char **argv)
{
    const char *image = NULL;
    const char *mountpoint = NULL;
    const char *fuse_argv[SFS_MAX_DEPTH + 16];
    int fa = 1;
    fuse_argv[0] = argv[0];

    for (int i = 1; i < argc; i++) {
        const char *a = argv[i];
        if (a[0] == '-') {
            if (fa < (int)(sizeof(fuse_argv) / sizeof(fuse_argv[0])) - 2)
                fuse_argv[fa++] = a;
            if (strcmp(a, "-o") == 0 && i + 1 < argc)
                fuse_argv[fa++] = argv[++i];
        } else if (image == NULL) {
            image = a;
        } else if (mountpoint == NULL) {
            mountpoint = a;
        } else if (fa < (int)(sizeof(fuse_argv) / sizeof(fuse_argv[0])) - 2) {
            fuse_argv[fa++] = a;
        }
    }

    if (image == NULL || mountpoint == NULL) {
        usage(argv[0]);
        return 2;
    }
    fuse_argv[fa++] = mountpoint;

    img_fd = open(image, O_RDWR);
    if (img_fd < 0) {
        fprintf(stderr, "sfsmount: cannot open %s: %s\n", image, strerror(errno));
        return 1;
    }

    struct stat sb;
    if (fstat(img_fd, &sb) < 0) {
        fprintf(stderr, "sfsmount: cannot stat %s: %s\n", image, strerror(errno));
        return 1;
    }
    img_size = (uint64_t)sb.st_size;
    if (img_size < 3 * (uint64_t)SFS_SECTOR_SIZE) {
        fprintf(stderr, "sfsmount: %s is too small to be an SFS image\n", image);
        return 1;
    }

    if (sfsdd_load() < 0) {
        fprintf(stderr, "sfsmount: cannot read SFSDD sector from %s\n", image);
        return 1;
    }
    if (sfs_map_build() < 0) {
        fprintf(stderr, "sfsmount: cannot build sector map for %s\n", image);
        return 1;
    }
    mount_time = time(NULL);

    return fuse_main(fa, (char **)fuse_argv, &sfs_ops, NULL);
}