# tests/Makefile - CI build for the asx framework repo (self-contained).
# The example app (src/) and the root Makefile are NOT in this repo, so
# this builds the framework + a tiny fixture app (tests/app/) and produces
# ./server + static wasm per route for the hydration/SPA/fuzz suites.
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
APP_S    := $(wildcard $(APP)/*.asx) $(wildcard $(APP)/api/*/*.asx) $(wildcard $(APP)/*/page.asx)
PKG_OBJS := $(PKG_SRCS:$(PKG)/%.asm=$(BUILD)/pkg/%.o)
APP_OBJS := $(APP_ASM:$(APP)/%.asm=$(BUILD)/app/%.o) $(APP_S:$(APP)/%.asx=$(BUILD)/app/%.o) $(BUILD)/app/middleware.o
OBJS     := $(PKG_OBJS) $(APP_OBJS)

route_path = $(if $(filter $(APP)/not-found.asx,$1),/__not_found,$(if $(filter $(APP)/page.asx,$1),/,$(patsubst $(APP)/%/,/%,$(patsubst $(APP)/%/page.asx,/%,$(patsubst $(APP)/%/route.asx,/%,$1)))))

UI_CP := $(BUILD)/tools/ui-compile
UI_CP_SRC := $(PKG)/ui/compile.asm $(shell find $(PKG)/ui -name '*.asm' -o -name '*.inc')
UI_LIB := $(PKG)/wasm/draw.wat $(PKG)/wasm/text.wat $(PKG)/wasm/widgets.wat $(PKG)/wasm/components.wat

# per-route wasm: the ui-compile derives data-modules from the file path
# (get_ui_name: strips "/page.asx"). With APP=app, app/page.asx ->
# data-modules="/app/page.wasm" and app/about/page.asx ->
# "/app/about/page.wasm" - so the wasm files must land at static/<same>
# (the server's CWD is tests/, and http_serve_static resolves "static"+path
# relative to it - same layout as the root Makefile).
ui_wasm = static/$(patsubst %/page.asx,%,$1)/page.wasm
UI_WASMS := $(foreach s,$(filter %/page.asx,$(APP_S)),$(call ui_wasm,$(s)))

all: $(TARGET) $(UI_WASMS)

$(TARGET): $(OBJS)
	$(LD) -o $@ $^

$(BUILD)/pkg/%.o: $(PKG)/%.asm | $(BUILD)
	@mkdir -p $(dir $@)
	$(AS) -f elf64 -I $(PKG) -o $@ $<

# the glue module embeds wasm/glue.js via incbin - rebuild when it changes.
# glue.js is GENERATED from wasm/glue/*.js modules (see root Makefile).
$(PKG)/wasm/glue.js: $(wildcard $(PKG)/wasm/glue/*.js)
	@cat $(sort $(wildcard $(PKG)/wasm/glue/*.js)) > $@
$(BUILD)/pkg/wasm/glue.o: $(PKG)/wasm/glue.js

$(BUILD)/app/%.o: $(APP)/%.asm | $(BUILD)
	@mkdir -p $(dir $@)
	$(AS) -f elf64 -I $(PKG) -I $(APP) -P$(PKG)/asx.inc -o $@ $<

# page.asx: @ DSL -> shell HTML + .wat per component, then nasm -> .o
$(BUILD)/app/%.s: $(APP)/%.asx $(UI_CP) | $(BUILD)
	@mkdir -p $(dir $@)
	$(UI_CP) $< $@

$(BUILD)/app/%.o: $(BUILD)/app/%.s | $(BUILD)
	$(AS) -f elf64 -I $(PKG) -I $(APP) -P$(PKG)/asx.inc -DROUTE_PATH=\"$(call route_path,$(APP)/$*.asx)\" -o $@ $<

$(UI_CP): $(UI_CP_SRC) | $(BUILD)
	@mkdir -p $(dir $@)
	$(AS) -f elf64 -I $(PKG) -o $(BUILD)/tools/ui-compile.o $<
	$(LD) -o $@ $(BUILD)/tools/ui-compile.o

# per-route wasm module: framework lib + the page's component wats + _main.
# NOTE: use the SHELL glob (*.wat) not $(wildcard ...) - GNU Make expands
# $(wildcard) in a recipe at parse time (before the deps run), so a clean
# CI build would see an empty list. Shell globs run at execution time.
$(BUILD)/app/%.s.wasm: $(BUILD)/app/%.s $(wildcard $(BUILD)/app/%.s.d/*.wat) $(UI_LIB) | $(BUILD)
	@mkdir -p $(dir $@)
	{ echo "(module"; cat $(UI_LIB) $(wildcard $(BUILD)/app/$*.s.d/*.wat); echo ")"; } | $(WAT2WASM) - -o $@

$(foreach s,$(filter %/page.asx,$(APP_S)),$(eval $(call ui_wasm,$(s)): $(BUILD)/$(patsubst $(APP)/%.asx,app/%.s.wasm,$(s)) ; @mkdir -p $$(dir $$@) && cp $$< $$@))

$(BUILD):
	mkdir -p $(BUILD)

.PHONY: all
