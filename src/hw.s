; hw.s - Oric Atmos hardware layer
;
; The ROM is not used: interrupts are masked, VIA timer 1 runs free at 50Hz
; only so the main loop can pace itself, the keyboard matrix is scanned
; directly and the AY-3-8912 is driven through the VIA.

        .include "hw.inc"

        .export hw_init, wait_frame, kbd_scan, key_row, key_down, any_key
        .export keys, ay_set, ay_reg, ay_val, ay_silence
        .exportzp frame_count
        .exportzp cb1s                          ; sim/emulator debug

        .zeropage
frame_count: .res 1
kacc:   .res 1
krow:   .res 1
cb1s:   .res 1                  ; 1 = wait on the CB1 VBLANK flag, 0 = T1

        .bss
keys:   .res 8                  ; matrix, bit set = key down
cb1cnt: .res 1                  ; flag count during the sync detection

        .code

; ---------------------------------------------------------------------------
; hw_init - take the machine over.  Returns with interrupts still masked.
hw_init:
        sei
        cld
        ; NB: no TXS here - the C runtime already set the stack up and a reset
        ; of it would destroy our own return address.
        lda #$7F
        sta VIA_IER             ; mask every VIA interrupt source
        lda #$F7
        sta VIA_DDRB            ; PB3 = keyboard sense input
        lda #$FF
        sta VIA_DDRA
        lda #$DD
        sta VIA_PCR             ; AY bus idle
        lda #$40
        sta VIA_ACR             ; T1 free run
        lda #<19998
        sta VIA_T1CL
        lda #>19998
        sta VIA_T1CH            ; 20ms period
        lda VIA_IFR             ; clear anything pending
        ; keyboard sense line low, all AY channels off
        lda #14
        ldx #$FF
        jsr ay_set
        lda #7
        ldx #$FF                ; both AY ports output: the keyboard columns
        jsr ay_set              ; are driven through port A
        lda #8
        ldx #0
        jsr ay_set
        lda #9
        ldx #0
        jsr ay_set
        lda #10
        ldx #0
        jsr ay_set
        lda #0
        sta frame_count
        ; Frame sync: on the Oric the monitor's VBLANK arrives on VIA CB1 as
        ; a ~260us low pulse once per frame (PCR $DD selects the positive
        ; edge, so the flag fires right after the pulse).  Sample it for
        ; three T1 ticks: no pulse or a tape driving CB1 (many flags per
        ; frame) falls back to the free-running T1 tick, which is NOT synced
        ; to the raster and shows as flicker while sprites move.
        lda VIA_IFR
        lda #$10
        sta VIA_IFR             ; clear a stale CB1 flag (write 1 to clear)
        lda #0
        sta cb1cnt
        ldx #3
@det:   jsr wait_t1
        lda VIA_IFR
        and #$10
        beq @nxt
        sta VIA_IFR             ; clear the flag
        inc cb1cnt
@nxt:   dex
        bne @det
        lda #0                  ; tape/no signal: T1 fallback
        ldy cb1cnt
        beq @have               ; zero flags: no CB1 signal
        cpy #20                 ; more than ~6 per frame: the tape
        bcs @have
        lda #1                  ; one-ish pulse every frame: the VBLANK
@have:  sta cb1s
        rts

; ---------------------------------------------------------------------------
; ay_reg: A = register.  ay_val: A = value.  ay_set: A = register, X = value.
; All preserve X and Y.
ay_reg:
        sta VIA_ORA
        lda #$FF
        sta VIA_PCR
        lda #$DD
        sta VIA_PCR
        rts

ay_val:
        sta VIA_ORA
        lda #$FD
        sta VIA_PCR
        lda #$DD
        sta VIA_PCR
        rts

ay_set:
        php
        sei
        pha
        jsr ay_reg
        txa
        jsr ay_val
        pla
        plp
        rts

; ay_silence - volume 0 on all three channels
ay_silence:
        php
        sei
        ldx #0
        lda #8
        jsr ay_set
        lda #9
        jsr ay_set
        lda #10
        jsr ay_set
        plp
        rts

; wait_t1 - block for one T1 tick (no frame_count, no Z requirement)
wait_t1:
        lda VIA_IFR
        and #$40                ; T1
        beq wait_t1
        lda VIA_T1CL            ; acknowledge
        rts

; ---------------------------------------------------------------------------
; wait_frame - block until the next frame.  Synced to the VBLANK pulse on
; CB1 when that was detected at init (which keeps the sprite erase/stamp in
; the blanking window, off the raster), otherwise the original 20ms T1 tick.
wait_frame:
        lda cb1s
        bne @cb
@l:     lda VIA_IFR
        and #$40                ; T1
        beq @l
        lda VIA_T1CL            ; acknowledge
        jmp @have
@cb:    lda VIA_IFR
        and #$10                ; CB1 flag
        beq @cb
        sta VIA_IFR             ; write the bit back to clear it
@have:  inc frame_count
        lda #0
        rts

; ---------------------------------------------------------------------------
; kbd_scan - read the 8x8 key matrix into keys[row] (bit = column, 1 = down)
kbd_scan:
        php
        sei
        lda #14
        jsr ay_reg
        ldx #7
@row:   stx krow
        lda VIA_ORB
        and #$F8
        ora krow
        sta VIA_ORB
        lda #0
        sta kacc
        ldy #7
@col:   lda colmask,y
        sta VIA_ORA
        lda #$FD
        sta VIA_PCR
        lda #$DD
        sta VIA_PCR
        nop
        nop
        nop
        nop
        lda VIA_ORB
        and #$08
        cmp #$08                ; C = 1 when the key is down
        rol kacc
        dey
        bpl @col
        lda kacc
        sta keys,x
        dex
        bpl @row
        plp
        rts

colmask: .byte $FE,$FD,$FB,$F7,$EF,$DF,$BF,$7F

; ---------------------------------------------------------------------------
; key_row: X = matrix row -> A = columns held (bit set = key down).
; Preserves X and Y.
key_row:
        php
        sei
        lda #14
        jsr ay_reg
        stx krow
        lda VIA_ORB
        and #$F8
        ora krow
        sta VIA_ORB
        tya
        pha
        lda #0
        sta kacc
        ldy #7
@col:   lda colmask,y
        sta VIA_ORA
        lda #$FD
        sta VIA_PCR
        lda #$DD
        sta VIA_PCR
        nop
        nop
        nop
        nop
        lda VIA_ORB
        and #$08
        cmp #$08
        rol kacc
        dey
        bpl @col
        pla
        tay
        lda kacc
        plp
        cmp #0                  ; Z set when no key in this row
        rts

; ---------------------------------------------------------------------------
; key_down: X = row, A = column mask -> Z set when that key is down
key_down:
        pha
        jsr key_row
        sta kacc
        pla
        and kacc
        rts

; any_key: A != 0 when any key is held
any_key:
        ldx #7
@r:     jsr key_row
        bne @yes
        dex
        bpl @r
        lda #0
        rts
@yes:   lda #$FF
        rts
