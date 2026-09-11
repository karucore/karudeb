#	Makefile
#	2024-07-25	Markku-Juhani O. Saarinen <mjos@iki.fi>. See LICENSE.

XBIN	?=	xmlkem
CSRC	=	$(wildcard *.c)
OBJS	= 	$(CSRC:.c=.o)

VK_KECCAK	?=	1
MLKEM_RVV	?=	1

XCHAIN	=	riscv64-unknown-linux-gnu-
CC 		=	$(XCHAIN)clang
RVKISA	?=	rv64gcv_zvl256b
#RVKISA	?=	rv64gc
CFLAGS	+=	-Wall -Wextra -Wshadow -DNDEBUG -O3 -g
#CFLAGS	+=	-Wall -Wextra -Wshadow -fsanitize=address,undefined -O2 -g
CFLAGS	+=	-march=$(RVKISA)
CFLAGS	+=	-DVK_KECCAK=$(VK_KECCAK)
CFLAGS	+=	-DMLKEM_RVV=$(MLKEM_RVV)
LDFLAGS	+=	-static --sysroot=$(RISCV)/sysroot/usr
LDLIBS	+=

#	maximum isa string for spike
SPIKEFL	=	--isa=rv64gcv_zbb_zvbb_zvbc_zvkg_zvkned_zvknhb_zvksed_zvksh_zvl256b_zvknhk_zicntr_zihpm

#	xtest
$(XBIN):	$(OBJS)
	$(CC) $(LDFLAGS) $(CFLAGS) -o $(XBIN) $(OBJS) $(LDLIBS)

run:	$(XBIN)
	spike $(SPIKEFL) pk -p $(XBIN)

kat:	$(XBIN)
	spike $(SPIKEFL) pk $(XBIN) refkat/ml-kem-kat.txt

%.o:	%.[csS]
	$(CC) $(CFLAGS) -c $^ -o $@

obj-clean:
	rm -f $(XBIN) $(OBJS)

clean:	obj-clean
	$(RM) -rf $(XBIN).* *.rsp *.req *.dis

