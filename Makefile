
MACHINE	     = UPET


CC           = cc65
AS           = ca65
LD           = ld65

# global includes
ASFLAGS     += -I inc
# for GEOS
#ASFLAGS     += -D bsw=1 -D drv1541=1 -I geos/inc -I geos
# for monitor
#ASFLAGS     += -D CPU_65C02=1
# KERNAL version number
ASFLAGS     +=  $(VERSION_DEFINE)
# put all symbols into .sym files
ASFLAGS     += -g

ASFLAGS     += -D MACHINE_UPET=1
ASFLAGS     += --cpu 65SC02

BUILD_DIR=build/$(MACHINE)

CFG_DIR=$(BUILD_DIR)/cfg

DOS_SOURCES = \
	dos/fat32/fat32.s \
	dos/fat32/mkfs.s \
	dos/fat32/sdcard.s \
	dos/fat32/text_input.s \
	dos/zeropage.s \
	dos/jumptab.s \
	dos/main.s \
	dos/match.s \
	dos/file.s \
	dos/cmdch.s \
	dos/dir.s \
	dos/parser.s \
	dos/functions.s 


GENERIC_DEPS = \
	inc/banks.inc \

DOS_DEPS = \
	$(GENERIC_DEPS) \
	dos/fat32/fat32.inc \
	dos/fat32/lib.inc \
	dos/fat32/regs.inc \
	dos/fat32/sdcard.inc \
	dos/fat32/text_input.inc \
	dos/functions.inc \
	dos/vera.inc

DOS_OBJS     = $(addprefix $(BUILD_DIR)/, $(DOS_SOURCES:.s=.o))

ifeq ($(MACHINE),UPET)
	BANK_BINS = $(BUILD_DIR)/dos.bin
	ROM_LABELS=$(BUILD_DIR)/rom_labels.h
	ROM_LST=$(BUILD_DIR)/rom_lst.h
endif

all: $(BUILD_DIR)/dos.bin $(ROM_LABELS) $(ROM_LST)

clean:
	rm -rf $(BUILD_DIR)

$(CFG_DIR)/%.cfg: %.cfgtpl
	@mkdir -p $$(dirname $@)
	$(CC) -E $< -o $@

# TODO: Need a way to control lst file generation through a configuration variable.
$(BUILD_DIR)/%.o: %.s
	@mkdir -p $$(dirname $@)
	$(AS) $(ASFLAGS) -l $(BUILD_DIR)/$*.lst $< -o $@

# TODO: Need a way to control relist generation; don't try to do it if lst files haven't been generated!

# Bank 2 : DOS
$(BUILD_DIR)/dos.bin: $(DOS_OBJS) $(DOS_DEPS) $(CFG_DIR)/dos-$(MACHINE).cfg
	@mkdir -p $$(dirname $@)
	$(LD) -C $(CFG_DIR)/dos-$(MACHINE).cfg $(DOS_OBJS) -o $@ -m $(BUILD_DIR)/dos.map -Ln $(BUILD_DIR)/dos.sym
	./scripts/relist.py $(BUILD_DIR)/dos.map $(BUILD_DIR)/dos


$(BUILD_DIR)/rom_labels.h: $(BANK_BINS)
	./scripts/symbolize.sh 2 build/$(MACHINE)/dos.sym     > $@

$(BUILD_DIR)/rom_lst.h: $(BANK_BINS)
	./scripts/trace_lst.py 2 `find build/$(MACHINE)/ -name \*.rlst`   > $@

