; hw.inc - Oric Atmos hardware and the shape of the tennis court.
;
; The machine is a 48K Atmos: the ROM is left in place but never called, and
; the game owns the VIA, the ULA and the AY-3-8912 from hw_init onwards.

VIA_ORB  = $0300
VIA_DDRB = $0302
VIA_DDRA = $0303
VIA_T1CL = $0304
VIA_T1CH = $0305
VIA_T2CL = $0308
VIA_T2CH = $0309
VIA_ACR  = $030B
VIA_PCR  = $030C
VIA_IFR  = $030D
VIA_IER  = $030E
VIA_ORA  = $030F

; video
HIRES    = $A000                ; 200 lines x 40 bytes, 6 pixels per byte
TEXTBASE = $BB80                ; text page; its first byte holds the mode attribute
TEXTROWS = $BF68                ; 3 character rows below the HIRES picture
MODEREG  = $BFDF                ; the ULA's serial input port
CHARSET  = $9800                ; 128 glyphs of 8 bytes in HIRES mode
VID_END  = $BF40                ; one past the last HIRES byte

; A HIRES byte holds six pixels in bits 0-5 (bit 5 = leftmost); bit 6 must be
; set or the ULA treats the byte as an attribute byte, bit 7 inverts the six
; pixels.  BLANK is therefore $40 and not $00.
BLANK    = $40
INVERT   = $80

SCR_W    = 240
SCR_BYTES= 40
VIEW_Y   = 64                   ; the screen.s view helpers are not used by the
VIEW_H   = 128                  ; tennis view, but they are still linked in

; ---------------------------------------------------------------------------
; The court, seen from the commentary box.
;
; Depth runs 0 (far baseline, at the top of the picture) to 127 (near
; baseline, where you stand).  Seven bits of depth, not eight, because the
; ball's position is 8.8 fixed point: with a top of 127 a depth that runs off
; the far baseline goes negative and is still recognisable by its sign bit.
; Depth is projected to a screen line by
;   line = ROW_FAR + (depth * 9) >> 3                 (depth * 144/128)
; and the half width of the court at that line is
;   halfw = HALFW_MIN + (depth >> 1) - (depth >> 4)   (depth * 60/128)
; so the far baseline is 104 pixels wide and the near one 216.
;
; Across the court, x runs 64..192 between the sidelines with the centre line
; at 128, so a ball can be well outside the lines and still be on screen:
;   screen x = 120 + ((x - 128) * halfw) >> 6
ROW_FAR    = 40                 ; first line of the far baseline
HALFW_MIN  = 52                 ; half width at the far baseline
COURT_CX   = 120                ; pixel column of the centre line
NET_DEPTH  = 64
SERV_FAR   = 30                 ; depth of the far service line
SERV_NEAR  = 98                ; depth of the near service line
NET_H      = 12                 ; net height in pixels

; ---------------------------------------------------------------------------
; keyboard matrix positions (see tools/keys.py for the whole matrix).
; Row 4 holds SPACE and the four arrows; M is row 2 column 0.
K_SP_ROW  = 4
K_SP_COL  = $01
K_UP_ROW  = 4
K_UP_COL  = $08
K_LF_ROW  = 4
K_LF_COL  = $20
K_DN_ROW  = 4
K_DN_COL  = $40
K_RT_ROW  = 4
K_RT_COL  = $80
K_M_ROW   = 2
K_M_COL   = $01

; Oric colour numbers
C_BLACK  = 0
C_RED    = 1
C_GREEN  = 2
C_YELLOW = 3
C_BLUE   = 4
C_MAGENTA= 5
C_CYAN   = 6
C_WHITE  = 7
