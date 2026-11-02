# Match Point for the Oric Atmos.  Needs cc65 (cl65/ca65/ld65) and python3.
CL65    = cl65
BUILD   = build
TAP     = $(BUILD)/matchpoint.tap

CSRC    = src/main.c
ASRC    = src/match.s src/header.s src/hw.s src/screen.s data/font.s data/tables.s
INC     = src/hw.inc src/zp.inc

all: $(TAP)

$(TAP): $(CSRC) $(ASRC) $(INC)
	@mkdir -p $(BUILD)
	$(CL65) -t atmos -O -I src -C src/matchpoint.cfg --obj-path $(BUILD) \
	        -m $(BUILD)/matchpoint.map -Ln $(BUILD)/matchpoint.lbl \
	        -o $@ $(CSRC) $(ASRC)

run: $(TAP)
	tools/run.sh

sim: $(TAP)
	python3 tools/simrun.py --out $(BUILD)/sim.png

clean:
	rm -rf $(BUILD)

.PHONY: all run sim clean
