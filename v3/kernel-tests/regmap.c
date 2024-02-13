#include <errno.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>

enum {
	MODE_HEX,
	MODE_DEC,
};

struct reg {
	char *name;
	uint32_t offset;
	int mode;
};

struct regmap {
	char *name;
	struct reg *regs;
	uint32_t addr;
	uint32_t size;
};

#include "regmap.h"

volatile void *map_regmap(struct regmap *regmap)
{
	int fd;
	void *mem;
	uint32_t addr_start;
	uint32_t addr_end;

	fd = open("/dev/mem", O_RDWR | O_SYNC);
	if (fd == -1)
		return NULL;

	addr_start = regmap->addr & ~0xfff;
	addr_end = regmap->addr + regmap->size;
	addr_end += -addr_end & 0xfff;

	mem = mmap(NULL, addr_end - addr_start, PROT_READ | PROT_WRITE,
		   MAP_SHARED, fd, addr_start);
	if (mem == MAP_FAILED)
		mem = NULL;
	else
		mem += regmap->addr & 0xfff;

	close(fd);

	return mem;
}

uint32_t read_reg(struct reg *reg, volatile void *mem)
{
	return *(volatile uint32_t *)(mem + reg->offset);
}

void write_reg(struct reg *reg, volatile void *mem, uint32_t val)
{
	*(volatile uint32_t *)(mem + reg->offset) = val;
}

int longest_name(struct regmap *regmap)
{
	struct reg *reg;
	int len;
	int longest = 0;

	for (reg = regmap->regs; reg->name; reg++) {
		len = strlen(reg->name);
		if (longest < len)
			longest = len;
	}

	return longest;
}

void print_reg(struct reg *reg, volatile void *mem, int pad)
{
	int len;
	uint32_t val;

	printf("%04x %s ", reg->offset, reg->name);

	len = strlen(reg->name);
	for (; len < pad; len++)
		printf(" ");

	val = read_reg(reg, mem);
	switch (reg->mode) {
	case MODE_HEX:
		printf("0x%x\n", val);
		break;
	case MODE_DEC:
		printf("%d\n", val);
		break;
	}
}

void print_regmap(struct regmap *regmap, volatile void *mem)
{
	struct reg *reg;
	int longest;

	longest = longest_name(regmap);

	for (reg = regmap->regs; reg->name; reg++)
		print_reg(reg, mem, longest);
}

void print_regmap_names(void)
{
	struct regmap *regmap;

	for (regmap = regmaps; regmap->name; regmap++)
		printf("%08x %s\n", regmap->addr, regmap->name);
}

struct regmap *find_regmap(char *name)
{
	struct regmap *regmap;

	for (regmap = regmaps; regmap->name; regmap++) {
		if (!strcmp(regmap->name, name))
			return regmap;
	}

	return NULL;
}

struct reg *find_reg(struct regmap *regmap, char *name)
{
	struct reg *reg;

	for (reg = regmap->regs; reg->name; reg++) {
		if (!strcmp(reg->name, name))
			return reg;
	}

	return NULL;
}

int main(int argc, char **argv)
{
	volatile void *mem;
	struct regmap *regmap;
	struct reg *reg;
	uint32_t val;

	if (argc == 1) {
		print_regmap_names();
		return 0;
	}

	regmap = find_regmap(argv[1]);
	if (!regmap) {
		fprintf(stderr, "regmap: %s: no such regmap\n", argv[1]);
		return 1;
	}

	mem = map_regmap(regmap);
	if (!mem) {
		fprintf(stderr, "regmap: mmap failed: %s\n", strerror(errno));
		return 1;
	}

	if (argc == 2) {
		print_regmap(regmap, mem);
		return 0;
	}

	reg = find_reg(regmap, argv[2]);
	if (!reg) {
		fprintf(stderr, "regmap: %s: no such register in %s\n", argv[2], argv[1]);
		return 1;
	}

	if (argc == 3) {
		print_reg(reg, mem, 0);
		return 0;
	}

	val = strtoul(argv[3], NULL, 0);
	write_reg(reg, mem, val);
	print_reg(reg, mem, 0);

	return 0;
}
