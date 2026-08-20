# tests/Makefile - CI build for the asx framework repo (self-contained).
# The example app (src/) and the root Makefile are NOT in this repo, so
# this builds the framework + a tiny fixture app (tests/app/) and produces
# ./server + static/index.wasm for the hydration/fuzz suites.
# Mirrors the root Makefile rules (nasm + ld + wat2wasm, no libc).
AS      := nasm
LD      := ld
WAT2WASM := wat2wasm
PKG     := ..
APP     := app
BUILD   := build
TARGET  := $(BUILD)/server

# framework sources (asx/, common/, http/, json/, net/) - everything
# except ui/ (the DSL compiler tool) and tests/
PKG_SRCS := $(shell find $(PKG) -name '*.asm' ! -path '$(PKG)/ui/*' ! -path '$(PKG)/tests/*')
APP_ASM  := $(wildcard $(APP)/*.asm)
APP_S    := $(wildcard $(APP)/*.s) $(wildcard $(APP)/api/*/*.s)
PKG_OBJS := $(PKG_SRCS:$(PKG)/%.asm=$(BUILD)/pkg/%.o)
APP_OBJS := $(APP_ASM:$(APP)/%.asm=$(BUILD)/app/%.o) $(APP_S:$(APP)/%.s=$(BUILD)/app/%.o) $(BUILD)/app/middleware.o
OBJS     := $(PKG_OBJS) $(APP_OBJS)

route_path = $(if $(filter $(APP)/not-found.s,$1),/__not_found,$(if $(filter $(APP)/page.s,$1),/,$(patsubst $(APP)/%/,/%,$(patsubst $(APP)/%/page.s,/%,$(patsubst $(APP)/%/route.s,/%,$1)))))

UI_CP := $(BUILD)/tools/ui-compile
UI_CP_SRC := $(PKG)/ui/compile.asm $(shell find $(PKG)/ui -name '*.asm' -o -name '*.inc')
UI_LIB := $(PKG)/wasm/draw.wat $(PKG)/wasm/text.wat $(PKG)/wasm/widgets.wat $(PKG)/wasm/components.wat

all: $(TARGET) $(BUILD)/static/index.wasm

$(TARGET): $(OBJS)
	$(LD) -o $@ $^

$(BUILD)/pkg/%.o: $(PKG)/%.asm | $(BUILD)
	@mkdir -p $(dir $@)
	$(AS) -f elf64 -I $(PKG) -o $@ $<

$(BUILD)/app/%.o: $(APP)/%.asm | $(BUILD)
	@mkdir -p $(dir $@)
	$(AS) -f elf64 -I $(PKG) -I $(APP) -P$(PKG)/asx.inc -o $@ $<

# page.s: @ DSL -> shell HTML + .wat per component, then nasm -> .o
$(BUILD)/app/%.s: $(APP)/%.s $(UI_CP) | $(BUILD)
	@mkdir -p $(dir $@)
	$(UI_CP) $< $@

$(BUILD)/app/%.o: $(BUILD)/app/%.s | $(BUILD)
	$(AS) -f elf64 -I $(PKG) -I $(APP) -P$(PKG)/asx.inc -DROUTE_PATH=\"$(call route_path,$(APP)/$*.s)\" -o $@ $<

$(UI_CP): $(UI_CP_SRC) | $(BUILD)
	@mkdir -p $(dir $@)
	$(AS) -f elf64 -I $(PKG) -o $(BUILD)/tools/ui-compile.o $<
	$(LD) -o $@ $(BUILD)/tools/ui-compile.o

# index.wasm: framework lib + the page's component wats + _main.
# NOTE: use the SHELL glob (*.wat) not $(wildcard ...) - GNU Make expands
# $(wildcard) in a recipe at parse time (before the deps run), so a clean
# CI build would see an empty list. Shell globs run at execution time.
$(BUILD)/static/index.wasm: $(BUILD)/app/page.s $(wildcard $(BUILD)/app/page.s.d/*.wat) $(UI_LIB) | $(BUILD)
	@mkdir -p $(dir $@)
	{ echo "(module"; cat $(UI_LIB) $(BUILD)/app/page.s.d/*.wat; echo ")"; } | $(WAT2WASM) - -o $@

$(BUILD):
	mkdir -p $(BUILD)

.PHONY: all
