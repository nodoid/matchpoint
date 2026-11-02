; match.s - Match Point for the Oric Atmos
;
; A tennis match seen from the commentary box: the court is drawn in
; perspective, you stand at the near baseline and the computer at the far one.
; The ball has a real height, so it can clear the net, bounce, or drop into it.
;
; The picture is HIRES (240x200 at $A000) with the three character rows under
; it for messages.  The court is static, so it is drawn once; the two players
; and the ball are saved and restored rather than the whole frame redrawn.
;
; Court coordinates: depth 0..255 from the far baseline to the near one, x
; 64..192 between the sidelines, z in pixels above the ground.

        .include "hw.inc"
        .include "zp.inc"

        .export _game_run
        .export main_loop, erase_all, draw_sprites   ; for tools/simrun.py
        .export p0_sx, p0_sy, p0_on, p1_sx, p1_sy, p1_on ; sim debug
        .export ball_sx, ball_sy, ba_on, ba_bc, ba_bl, ba_live, sh_bc, sh_bl ; sim debug
        .export buf_p0, buf_p1, p0_bc, p0_bl, p1_bc, p1_bl, buf_ball, buf_sh ; sim debug
        .export pose_off, spx, spy, spw, sph, sptr, bufptr, who_s, mv_s, ht_tick
        .export ply_save, ply_stamp, ball_save, ball_stamp   ; sim debug
        .export rect_save, rect_restore, shadow_save, shadow_stamp ; sim debug
        .import hw_init, wait_frame, kbd_scan, keys
        .import scr_init, text_clear, text_str, hline, vline, plotpix
        .import row_addr
        .import blit_or, blit_setup, gtext
        .import xtab
        .import ay_set
        .importzp frame_count
        .importzp cb1s

; states
ST_TITLE = 0
ST_SERVE = 1
ST_RALLY = 2
ST_POINT = 3
ST_SET   = 4
ST_OVER  = 5

; keys held this frame
KF_UP    = $01
KF_DOWN  = $02
KF_LEFT  = $04
KF_RIGHT = $08
KF_FIRE  = $10
KF_ARROWS = KF_UP+KF_DOWN+KF_LEFT+KF_RIGHT

; sound ids
SFX_BOUNCE = 0
SFX_HIT    = 1
SFX_SERVE  = 2
SFX_NET    = 3
SFX_FAULT  = 4
SFX_WIN    = 5
SFX_LOSE   = 6
SFX_GAME   = 7
SFX_SET    = 8
SFX_MATCH  = 9
SFX_LOSM   = 10
SFX_BLIP   = 11

; 8.8 fixed point: 256 = one unit (court x/depth) or one pixel (height)
GRAV     = 16                   ; 16/256 px per frame per frame
HIT_VZ   = 576                  ; 2.25 px/frame up: about a 70 frame lob
RAMP_STEP= 64                   ; +0.25 px/frame of groundstroke pace per hit
RAMP_CAP_HI= 4                  ; cap the pace at 4.0 px/frame
SERVE_VZ = 256                  ; tuned so the serve clears the net and
                                ; lands inside the service box at either end
SPEED_Y  = 512                  ; 2 units/frame: about a 60 frame flight
NET_TOP  = 16                   ; the net top in ball height, plus grace
SERVE_FR = 45                   ; exact frames a serve spends in the air

PL_SPEED = 4                    ; player pixels per frame

REACH_P  = 26                   ; how far you can reach either side
HIT_Z    = 44                   ; the highest ball you can hit
REACH_ROW = 12                  ; the farthest the reach reaches along depth

        .bss
buf_p0:   .res 56                ; 14 lines x 4 cells
buf_p1:   .res 56
buf_ball: .res 8                 ; 2 lines x 4 cells
buf_sh:   .res 1                 ; the ball's shadow, one cell on the ground line
p0_bc:    .res 1                ; where each sprite was last drawn
p0_bl:    .res 1
p1_bc:    .res 1
p1_bl:    .res 1
ba_bc:    .res 1
ba_bl:    .res 1
sh_bc:    .res 1                ; the shadow's last drawn cell, registered by
sh_bl:    .res 1                ; its save so the erase hits the right place
p0_on:    .res 1
p1_on:    .res 1
ba_on:    .res 1                ; a ball/shadow rect is pending erase
ba_live:  .res 1                ; the ball is on screen this frame
who_s:    .res 1                ; which player draw_ply is drawing
mv_s:     .res 1                ; that player moved this frame
ht_tick:  .res 1                ; when the last stroke was hit (swing anim)
p0_savx:  .res 1                ; last frame's positions, to detect movement
p0_savy:  .res 1
p1_savx:  .res 1
p1_savy:  .res 1
cv_d:     .res 1                ; court drawing loop depth
chbuf:    .res 2
hc_col:   .res 1
hc_line:  .res 1
net_row:  .res 1
net_lx:   .res 1
net_rx:   .res 1
prev_by:  .res 1                ; ball depth last frame, to spot the net
last_row: .res 1                ; the last screen line the colour pass did
col_from: .res 1                ; the colour pass loop state, out of halfw's way
col_to:   .res 1
ro_margin: .res 1               ; width of the run-off at this depth

; service faults
faults:   .res 1                ; serves lost in this point (0, 1 or 2)
serve_in: .res 1                ; 1 while a serve has not yet landed legally
serve_side:.res 1               ; 0 = serve to the left box, 1 = to the right
bounced:  .res 1                ; the ball has pitched since it was struck
p_hold:   .res 1                ; the serve wait freezes the depth keys

; the championship
set_over: .res 1                ; one set has been won, the match has not

; the title screen's surface and opponent choices
surface:  .res 1                ; 0 slow, 1 medium, 2 fast
opp:      .res 1                ; 0 easy, 1 normal, 2 hard
speed_y:  .res 2                ; groundstroke and rally speed, 8.8
bounce_k: .res 1                ; the bounce keeps 2^k - 1 of the fall
ai_speed: .res 1                ; the computer's pixels per frame
reach_a:  .res 1                ; the computer's reach around its baseline

; the sound sequencer
snd_tmr:  .res 1                ; frames left on this step
; the ball ending in the net (0 = any other way the point can end)
ptwhy:   .res 1
; wins needed for the match (best of three sets)
SET_WINS = 2
prevk:    .res 1                ; keys held last frame, for menu edges

        .code

; ---------------------------------------------------------------------------
; _game_run - entry point.  The C runtime calls this and it never returns.
_game_run:
        jsr hw_init
        jsr scr_init
        lda #1                  ; medium surface, normal opponent
        sta surface
        sta opp
        lda #6
        ldx #12                 ; the pitch of the bounce and net noises
        jsr ay_set
        jsr new_match
        jsr court_draw          ; court_draw includes the colour pass
        jsr title_menu
        lda #ST_TITLE
        sta st

main_loop:
        jsr wait_frame
        jsr kbd_scan
        jsr read_keys
        jsr sfx_tick
        lda st
        cmp #ST_TITLE
        bne @a
        jsr st_title
        jmp main_loop
@a:     cmp #ST_SERVE
        bne @b
        jsr st_serve
        jmp main_loop
@b:     cmp #ST_RALLY
        bne @c
        jsr st_rally
        jmp main_loop
@c:     cmp #ST_POINT
        bne @d
        jsr st_point
        jmp main_loop
@d:     cmp #ST_SET
        bne @e
        jsr st_set
        jmp main_loop
@e:     jsr st_over
        jmp main_loop

; ---------------------------------------------------------------------------
; read_keys - latch the keys we care about into kflags.
read_keys:
        lda #0
        sta kflags
        lda keys+K_UP_ROW
        and #K_UP_COL
        beq @nup
        lda kflags
        ora #KF_UP
        sta kflags
@nup:   lda keys+K_DN_ROW
        and #K_DN_COL
        beq @ndn
        lda kflags
        ora #KF_DOWN
        sta kflags
@ndn:   lda keys+K_LF_ROW
        and #K_LF_COL
        beq @nlf
        lda kflags
        ora #KF_LEFT
        sta kflags
@nlf:   lda keys+K_RT_ROW
        and #K_RT_COL
        beq @nrt
        lda kflags
        ora #KF_RIGHT
        sta kflags
@nrt:   lda keys+K_SP_ROW
        and #K_SP_COL
        beq @m
        lda kflags
        ora #KF_FIRE
        sta kflags
@m:     lda keys+K_M_ROW
        and #K_M_COL
        beq @done
        lda kflags
        ora #KF_FIRE
        sta kflags
@done:  rts

; ---------------------------------------------------------------------------
; new_match - reset the score for a fresh match
new_match:
        lda #0
        sta pts
        sta pts+1
        sta pts+1
        sta games
        sta games+1
        sta sets
        sta sets+1
        sta srv
        sta over
        sta last_hit
        sta ht_tick
        sta prevf
        sta prevk
        sta faults
        sta serve_in
        sta serve_side
        sta bounced
        sta p_hold
        sta set_over
        sta ptwhy
        sta snd_ptr
        sta snd_ptr+1
        jsr apply_surf          ; keep the chosen surface and opponent
        jsr apply_opp
        lda #120
        sta p0y
        lda #128
        sta p0x
        lda #20
        sta p1y
        lda #128
        sta p1x
        jsr erase_all           ; drop any sprites a finished match baked in; a
        lda #0                  ; blank boot is a no-op, the flags are clear
        sta p0_on
        sta p1_on
        sta ba_on
        sta ba_live
        jmp hud_draw

; ---------------------------------------------------------------------------
; msg_put - A = message number, printed in the character rows
msg_put:
        sta msg_id
        jsr text_clear
        lda msg_id              ; text_clear leaves A = $20: reload first
        tax
        lda msg_lo,x
        sta txtptr
        lda msg_hi,x
        sta txtptr+1
        ldx #0
        ldy #0
        jmp text_str

; ---------------------------------------------------------------------------
; put_chr - A = character, X = byte column, Y = first line
put_chr:
        sta chbuf
        lda #0
        sta chbuf+1
        stx hc_col
        sty hc_line
        lda #<chbuf
        sta txtptr
        lda #>chbuf
        sta txtptr+1
        ldx hc_col
        ldy hc_line
        jmp gtext

; put_digit - A = 0..9, X = column, Y = line
put_digit:
        clc
        adc #48
        jmp put_chr

; ---------------------------------------------------------------------------
; hud_draw - the scoreboard banner across the top of the picture, in the
; shape of the Spectrum original but with both players' lines: headings on
; the first glyph row, your line beneath them, the computer's line under
; that, then two rows of crowd before the far baseline starts.
hud_draw:
        ; blank the top three character rows, then the crowd above the court
        lda #0
        sta tmp1
@clear: lda tmp1
        jsr row_addr
        lda #BLANK
        ldy #0
@clr:   sta (dptr),y
        iny
        cpy #SCR_BYTES
        bne @clr
        inc tmp1
        lda tmp1
        cmp #ROW_FAR
        bne @clear
        ; the crowd: a stipple band from just under the banner to the far line
        lda #26
        sta tmp1
@crowd: lda tmp1
        jsr row_addr
        lda tmp1
        and #1
        beq @even
        lda #$55
        jmp @cfill
@even:  lda #$2A                ; $2A has bit 6 clear, so use $6A for dots
        lda #$6A
@cfill: sta tmp2
        ldy #0
@cf:    tya
        and #1
        beq @dot
        lda #BLANK
        jmp @put
@dot:   lda tmp2
@put:   sta (dptr),y
        iny
        cpy #SCR_BYTES
        bne @cf
        inc tmp1
        lda tmp1
        cmp #32
        bne @crowd
        ; colour the stands: magenta on the left, cyan on the right
        lda #26
        sta tmp1
@stands:lda tmp1
        jsr row_addr
        ldy #0
        lda #$07                ; ink white
        sta (dptr),y
        lda tmp1
        and #1
        beq @standeven
        lda #$16                ; cyan on the left, magenta on the right
        ldy #1
        sta (dptr),y
        lda #$15
        ldy #20
        sta (dptr),y
        jmp @standnext
@standeven:
        lda #$15                ; magenta on the left, cyan on the right
        ldy #1
        sta (dptr),y
        lda #$16
        ldy #20
        sta (dptr),y
@standnext:
        inc tmp1
        lda tmp1
        cmp #32
        bne @stands
        ; the box around the banner
        lda #0
        ldx #239
        ldy #0
        jsr hline
        lda #0
        ldx #239
        ldy #25
        jsr hline
        lda #0
        ldx #0
        ldy #25
        jsr vline
        lda #239
        ldx #0
        ldy #25
        jsr vline
        ; the headings, your line, then the computer's line
        lda #<t_prev
        sta txtptr
        lda #>t_prev
        sta txtptr+1
        ldx #1
        ldy #1
        jsr gtext
        lda #<t_cols
        sta txtptr
        lda #>t_cols
        sta txtptr+1
        ldx #22
        ldy #1
        jsr gtext
        ; YOU 0 0 00
        lda #<t_name
        sta txtptr
        lda #>t_name
        sta txtptr+1
        ldx #1
        ldy #9
        jsr gtext
        lda sets
        ldx #22
        ldy #9
        jsr put_digit
        lda games
        ldx #28
        ldy #9
        jsr put_digit
        ldx pts
        lda pt_lo,x
        sta txtptr
        lda pt_hi,x
        sta txtptr+1
        ldx #35
        ldy #9
        jsr gtext
        ; COMPUTER 0 0 00
        lda #<t_cpu
        sta txtptr
        lda #>t_cpu
        sta txtptr+1
        ldx #1
        ldy #17
        jsr gtext
        lda sets+1
        ldx #22
        ldy #17
        jsr put_digit
        lda games+1
        ldx #28
        ldy #17
        jsr put_digit
        ldx pts+1
        lda pt_lo,x
        sta txtptr
        lda pt_hi,x
        sta txtptr+1
        ldx #35
        ldy #17
        jmp gtext

; ---------------------------------------------------------------------------
; depth_row - A = depth 0..255 -> A = screen line
depth_row:
        sta tmp1
        lda #0
        sta tmp2
        lda tmp1
        asl a
        rol tmp2
        asl a
        rol tmp2
        asl a
        rol tmp2                ; depth * 8
        clc
        adc tmp1
        sta tmp3
        lda tmp2
        adc #0
        sta tmp4                ; depth * 9, which is depth * 144 / 128
        ldx #3
@sh:    lsr tmp4
        ror tmp3
        dex
        bne @sh
        lda tmp3
        clc
        adc #ROW_FAR
        rts

; halfw - A = depth -> A = half the width of the court, in pixels
halfw:
        sta tmp1
        lsr a
        sta tmp2                ; depth >> 1
        lda tmp1
        lsr a
        lsr a
        lsr a
        lsr a                   ; depth >> 4
        sta tmp3
        lda tmp2
        sec
        sbc tmp3                ; depth * 60 / 128
        clc
        adc #HALFW_MIN
        rts

; side_x - A = depth, X = 0 for the left sideline or 1 for the right -> A = pixel
side_x:
        stx side_tmp
        jsr halfw
        sta tmp3
        lda #COURT_CX
        sec
        sbc tmp3
        sta tmp4                ; left
        lda #COURT_CX
        clc
        adc tmp3
        sta tmp5                ; right
        lda side_tmp
        beq @left
        lda tmp5
        rts
@left:  lda tmp4
        rts

; mul8 - A * X -> numlo/numhi (both unsigned)
mul8:
        sta mt_a
        stx mt_b
        lda #0
        sta numlo
        sta numhi
        ldx #8
@l:     asl numlo
        rol numhi
        asl mt_a
        bcc @n
        clc
        lda numlo
        adc mt_b
        sta numlo
        lda numhi
        adc #0
        sta numhi
@n:     dex
        bne @l
        rts

; proj_x - A = court x (64..192), X = half width -> A = pixel column
proj_x:
        stx mt_b
        sec
        sbc #128
        sta mt_sign             ; bit 7 set when the point is left of centre
        bpl @abs
        eor #$FF
        clc
        adc #1
@abs:   jsr mul8
        lda numhi
        sta tmp2
        lda numlo
        sta tmp1
        ldx #6                  ; (x - 128) * halfw / 64
@sh:    lsr tmp2
        ror tmp1
        dex
        bne @sh
        lda mt_sign
        bmi @left
        lda tmp1
        clc
        adc #COURT_CX
        cmp #240
        bcc @ok
        lda #239
@ok:    rts
@left:  lda #COURT_CX
        sec
        sbc tmp1
        bcs @ok
        lda #0
        rts

; ---------------------------------------------------------------------------
; court_draw - baselines, sidelines, service lines, centre line and the net
court_draw:
        lda #0
        jsr draw_courtline
        lda #127                ; depth is 0..127: the near baseline
        jsr draw_courtline
        lda #SERV_FAR
        jsr draw_courtline
        lda #SERV_NEAR
        jsr draw_courtline
        ; the two sidelines, one pixel per line of depth
        lda #0
        sta cv_d
@side:  lda cv_d
        jsr depth_row
        sta tmp6
        lda cv_d
        ldx #0
        jsr side_x
        ldx tmp6
        jsr plotpix
        lda cv_d
        ldx #1
        jsr side_x
        ldx tmp6
        jsr plotpix
        inc cv_d
        lda cv_d
        cmp #128                ; depth runs 0..127, so stop at the near line
        bne @side
        ; the centre service line
        lda #SERV_FAR
        jsr depth_row
        sta tmp1
        lda #SERV_NEAR
        jsr depth_row
        sta tmp2
        lda #COURT_CX
        ldx tmp1
        ldy tmp2
        jsr vline
        ; the net
        lda #NET_DEPTH
        jsr depth_row
        sta net_row
        lda #NET_DEPTH
        ldx #0
        jsr side_x
        sta net_lx
        lda #NET_DEPTH
        ldx #1
        jsr side_x
        sta net_rx
        ; the cord along the top
        lda net_row
        sec
        sbc #NET_H
        tay
        lda net_lx
        ldx net_rx
        jsr hline
        ; the base line of the net
        ldy net_row
        lda net_lx
        ldx net_rx
        jsr hline
        ; the mesh: a vertical every eight pixels
        lda net_lx
        sta tmp3
@mesh:  lda tmp3
        cmp net_rx
        bcs @posts
        lda net_row
        sec
        sbc #NET_H
        sta tmp4
        lda tmp3
        ldx tmp4
        ldy net_row
        jsr vline
        lda tmp3
        clc
        adc #3
        sta tmp3
        jmp @mesh
@posts: ; the two net posts, a little taller than the mesh
        lda net_row
        sec
        sbc #NET_H + 3
        sta tmp4
        lda net_lx
        ldx tmp4
        ldy net_row
        jsr vline
        lda net_rx
        ldx tmp4
        ldy net_row
        jsr vline
        jmp court_colour

; court_colour - colour the court rows.
;
; A byte whose bits 6 and 5 are both clear is a serial attribute: it sets the
; ink or the paper for the rest of that line, and is itself drawn as one cell
; of the new paper colour.  So a court line is black outside, yellow across the
; run-off, green for the court itself, then yellow and black again.
;
; The attributes are written after all the line work and sit one cell outside
; each sideline, so they never paint over the lines they bound.
court_colour:
        lda #$FF
        sta last_row
        lda #0
        sta cv_d
@next:  lda cv_d
        jsr depth_row
        sta col_to              ; the row this depth projects to
        cmp last_row
        beq @skip               ; this depth shares the previous row
        lda last_row
        cmp #$FF
        bne @first
        lda #ROW_FAR
        sec
        sbc #1
@first: sta col_from            ; colour last_row+1 .. col_to
@fill:  inc col_from
        lda col_from
        jsr colour_row
        lda col_from
        cmp col_to
        bne @fill
        lda col_to
        sta last_row
@skip:  inc cv_d
        lda cv_d
        cmp #128
        bne @next
        ; the yellow apron: a band above the far baseline and a deeper one
        ; below the near baseline, so the court sits in a yellow surround
        lda #ROW_FAR - 8
        sta half_w
        lda #ROW_FAR
        sta ground_row
        jsr apron
        lda #183
        sta half_w
        lda #200
        sta ground_row
        jmp apron

; apron - colour lines half_w .. ground_row-1 yellow across the whole width
apron:  lda half_w
        jsr row_addr
        ldy #0
        lda #$00                ; ink black
        sta (dptr),y
        iny
        lda #$13                ; paper yellow
        sta (dptr),y
        iny
        lda #BLANK              ; and blank the line, so the stands do not
@blank: sta (dptr),y            ; show through it
        iny
        cpy #SCR_BYTES
        bne @blank
        inc half_w
        lda half_w
        cmp ground_row
        bne apron
        rts

; colour_row - A = the screen line to colour
colour_row:
        sta half_w
        lda cv_d
        jsr halfw
        sta tmp3                ; half width at this depth
        lda half_w
        jsr row_addr
        ; black ink, black paper: the world outside the run-off
        ldy #0
        lda #$00
        sta (dptr),y
        iny
        lda #$10
        sta (dptr),y
        ; the run-off is a quarter of the half width plus a little, so it
        ; widens with the perspective the way the original's does
        lda tmp3
        lsr a
        lsr a
        clc
        adc #12
        sta ro_margin
        lda #COURT_CX
        sec
        sbc tmp3
        sta tmp4                ; sideline, pixels
        sec
        sbc ro_margin
        bcs @ol
        lda #0
@ol:    tax
        lda xtab,x
        sta tmp5                ; run-off edge, bytes
        lda tmp4
        tax
        lda xtab,x
        sta tmp6                ; sideline, bytes
        dec tmp6                ; one cell out, to leave the line alone
        ; the right hand side
        lda #COURT_CX
        clc
        adc tmp3
        sta tmp4
        tax
        lda xtab,x
        sta side_tmp
        inc side_tmp
        lda tmp4
        clc
        adc ro_margin
        cmp #240
        bcc @or
        lda #239
@or:    tax
        lda xtab,x
        sta ground_row
        ; now place them, left to right
        ldy tmp5
        cpy #2
        bcc @green
        lda #$13                ; paper yellow
        sta (dptr),y
@green: ldy tmp6
        beq @noline             ; the sideline is in the first cell
        dey
        lda #$07                ; ink white: the court's line work
        sta (dptr),y
@noline: ldy tmp6
        lda #$12                ; paper green
        sta (dptr),y
        ldy side_tmp
        cpy #39
        bcs @done
        lda #$13                ; paper yellow
        sta (dptr),y
        iny
        cpy #39
        bcs @done
        lda #$10                ; paper black
        sta (dptr),y
@done:  rts

; draw_courtline - A = depth -> a horizontal line across the court
draw_courtline:
        sta side_tmp
        jsr depth_row
        sta tmp6
        lda side_tmp
        ldx #0
        jsr side_x
        sta tmp4
        lda side_tmp
        ldx #1
        jsr side_x
        sta tmp5
        lda tmp4
        ldx tmp5
        ldy tmp6
        jmp hline

; ---------------------------------------------------------------------------
; rect_save / rect_restore - copy the spw x sph rectangle at (spx, spy)
; between the screen and the buffer at bufptr.
rect_save:
        jsr rect_addr           ; dptr = the screen
        lda dptr
        sta sptr
        lda dptr+1
        sta sptr+1
        lda bufptr
        sta dptr
        lda bufptr+1
        sta dptr+1
        lda sph
        sta cnt
@row:   ldy #0
@col:   lda (sptr),y
        sta (dptr),y
        iny
        cpy spw
        bne @col
        clc
        lda sptr
        adc #SCR_BYTES
        sta sptr
        bcc @n1
        inc sptr+1
@n1:    clc
        lda dptr
        adc spw
        sta dptr
        bcc @n2
        inc dptr+1
@n2:    dec cnt
        bne @row
        rts

rect_restore:
        jsr rect_addr           ; dptr = the screen
        lda bufptr
        sta sptr
        lda bufptr+1
        sta sptr+1
        lda sph
        sta cnt
@row:   ldy #0
@col:   lda (sptr),y
        sta (dptr),y
        iny
        cpy spw
        bne @col
        clc
        lda sptr
        adc spw
        sta sptr
        bcc @n1
        inc sptr+1
@n1:    clc
        lda dptr
        adc #SCR_BYTES
        sta dptr
        bcc @n2
        inc dptr+1
@n2:    dec cnt
        bne @row
        rts

; rect_addr - dptr = address of (spx, spy)
rect_addr:
        lda spy
        ldx spx
        jmp blit_setup

; ---------------------------------------------------------------------------
; erase_all - put back whatever was under the sprites.
;
; Rects are restored in the reverse of the order they were saved, so any cell
; several sprites overlapped ends up holding the background saved before
; anything was drawn there: that is what stops old sprite pixels from
; reappearing inside a later sprite's rectangle.
;
; Each rect is exactly the footprint its draw used and sits at the same
; cell, in the reverse of the draw order; the shadow patches a single cell
; left of the ball dot.
erase_all:
        lda ba_on
        beq @bl
        lda #<buf_sh
        sta bufptr
        lda #>buf_sh
        sta bufptr+1
        lda sh_bc
        sta spx                   ; the shadow's registered cell, not a
        lda sh_bl                 ; re-derivation off a moving ground_row
        sta spy
        lda #1
        sta spw
        lda #1
        sta sph
        jsr rect_restore
@bl:    lda ba_on
        beq @p1
        lda #<buf_ball
        sta bufptr
        lda #>buf_ball
        sta bufptr+1
        lda ba_bc
        sta spx
        lda ba_bl
        sta spy
        lda #4
        sta spw
        lda #2
        sta sph
        jsr rect_restore
        lda #0
        sta ba_on
@p1:    lda p1_on
        beq @p0
        lda #<buf_p1
        sta bufptr
        lda #>buf_p1
        sta bufptr+1
        lda p1_bc
        sta spx
        lda p1_bl
        sta spy
        lda #4
        sta spw
        lda #14
        sta sph
        jsr rect_restore
        lda #0
        sta p1_on
@p0:    lda p0_on
        beq @done
        lda #<buf_p0
        sta bufptr
        lda #>buf_p0
        sta bufptr+1
        lda p0_bc
        sta spx
        lda p0_bl
        sta spy
        lda #4
        sta spw
        lda #14
        sta sph
        jsr rect_restore
        lda #0
        sta p0_on
@done:  rts

; ---------------------------------------------------------------------------
; proj_players / proj_ball - court coordinates to screen positions
proj_players:
        lda p0y
        jsr depth_row
        sec
        sbc #11
        cmp #186                ; the sprite ends 14 rows below this
        bcc @yok0
        lda #186
@yok0:  sta p0_sy
        lda p0y
        jsr halfw
        sta half_w
        lda p0x
        ldx half_w
        jsr proj_x
        sta p0_sx
        lda p1y
        jsr depth_row
        sec
        sbc #11
        cmp #186
        bcc @yok1
        lda #186
@yok1:  sta p1_sy
        lda p1y
        jsr halfw
        sta half_w
        lda p1x
        ldx half_w
        jsr proj_x
        sta p1_sx
        rts

proj_ball:
        lda byh
        jsr depth_row
        sta ground_row
        lda byh
        jsr halfw
        sta half_w
        lda bxh
        ldx half_w
        jsr proj_x
        sta ball_sx
        lda ground_row
        sec
        sbc bzh
        bcs @zok
        lda #0
@zok:   sta ball_sy
        rts

; ---------------------------------------------------------------------------
; Sprites.
;
; Everything is drawn on 6-pixel cells, but a full-cell-wide figure looks
; squat and moves in jerks, so each sprite is split into a cell position and a
; 0..5 pixel offset, and pre-shifted copies of it are stamped with a mask that
; clears the figure's pixels.  Clearing draws them in the row's ink - black,
; like the original's players - and an explicit paper-black attribute one cell
; to the left keeps them black even where the court's own attributes are
; running white and coloured; the original colour byte right of the sprite is
; copied back from the save buffer every row, so the court's attribute stream
; resules exactly as it was.
;
; split_x - A = pixel column -> X = byte column, A = pixel offset 0..5
split_x:
        sta tmp4
        jsr xtab_lookup
        tax
        txa
        asl a
        sta tmp5                ; 2L
        asl a
        clc
        adc tmp5                ; 6L
        sta tmp5
        lda tmp4
        sec
        sbc tmp5                ; the pixel offset
        rts

; pose_pick - choose a pose and set sptr to its shift table.
;   swing for 12 frames after this player struck the ball, otherwise a two
;   stage stride while moving and a still pose when not.
pose_pick:
        sec
        lda tick
        sbc ht_tick
        cmp #12
        bcc @swing
        lda who_s
        cmp last_hit
        bne @nswing
@swing: lda #2
        jmp @have
@nswing: lda mv_s
        beq @still
        lda tick
        lsr a
        lsr a
        lsr a
        and #1
        jmp @have
@still: lda #0
@have:  sta tmp3                ; the pose, 0..2
        lda tmp3                ; the word index: (offset + 6 x pose) x 2
        asl a
        sta tmp4
        asl a
        clc
        adc tmp4                ; the pose, times six
        clc
        adc tmp2                ; plus the pixel offset
        asl a                   ; the word index into the offset table
        tay
        lda pose_off,y
        sta sptr
        iny
        lda pose_off,y
        sta sptr+1
        clc
        lda sptr
        adc #<ply_f0
        sta sptr
        lda sptr+1
        adc #>ply_f0
        sta sptr+1
        rts

; the sprite layer runs as a SAVE pass then a STAMP pass.  Every sprite
; saves its rect from a screen nothing has been stamped on yet this frame,
; so the buffers never capture another sprite's pixels - that is what keeps
; the erase from painting ghosts inside a later sprite's rect.
;
; Every rect is the sprite's own cells plus the two cells right of them:
; while the figure is on screen those cells carry the saved court bytes, so
; the court's colour stream resumes twelve pixels right of the sprite, and
; the erase puts the whole neighbourhood back in one go.

; ply_save - A = pixel column, Y = the top screen line; bufptr and who_s
; already set by the caller.
ply_save:
        jsr split_x
        cpx #36
        bcc @c
        ldx #36
@c:     stx tmp2                ; the cell
        tya
        sta spy
        lda #4                  ; two figure cells + the two carry cells
        sta spw
        lda #14
        sta sph
        ldy who_s
        beq @p0
        lda tmp2
        sta spx
        sta p1_bc
        lda spy
        sta p1_bl
        jmp rect_save
@p0:    lda tmp2
        sta spx
        sta p0_bc
        lda spy
        sta p0_bl
        jmp rect_save

; ply_stamp - stamp the (already saved) figure: the cell, line and pose are
; re-derived from the same values the save used, and the two saved court
; bytes are carried twelve pixels right so the colour stream resumes there.
ply_stamp:
        lda who_s
        beq @p0
        lda p1_bl
        sta spy
        lda p1_bc
        sta spx
        lda p1_sx
        jmp @go
@p0:    lda p0_bl
        sta spy
        lda p0_bc
        sta spx
        lda p0_sx
@go:    jsr split_x             ; the pixel offset drives the pose
        sta tmp2
        jsr pose_pick
        lda #14
        sta cnt
@row:   lda spy
        ldx spx
        jsr blit_setup
        ldy #0
        lda (sptr),y
        sta (dptr),y            ; pure replace, not OR: the figure must
        ldy #1                  ; occlude the pixels under it and must not
        lda (sptr),y            ; fold a sprite byte into a court attribute
        sta (dptr),y            ; cell (an OR of $12|$4E = $5E turns a
        ldy #0                  ; paper-green attr into stray white pixels,
        lda (bufptr),y          ; the source of the blobs downstream)
        ldy #2
        sta (dptr),y
        ldy #1
        lda (bufptr),y
        ldy #3
        sta (dptr),y
        inc spy
        clc
        lda dptr
        adc #SCR_BYTES
        sta dptr
        bcc @nc1
        inc dptr+1
@nc1:   clc
        lda bufptr
        adc #4
        sta bufptr
        bcc @nc2
        inc bufptr+1
@nc2:   clc
        lda sptr
        adc #2
        sta sptr
        bcc @nc3
        inc sptr+1
@nc3:   dec cnt
        bne @row
        rts

; ball_save - A = pixel column, Y = the top screen line, bufptr = buf_ball.
ball_save:
        jsr split_x
        cpx #36
        bcc @c
        ldx #36
@c:     tya
        beq @gone               ; never drawn on line 0
        cmp #198
        bcc @ln
        lda #197
@ln:    sta ba_bl
        sta spy
        txa
        sta ba_bc
        sta spx
        lda #4
        sta spw
        lda #2
        sta sph
        lda #<buf_ball
        sta bufptr
        lda #>buf_ball
        sta bufptr+1
        jsr rect_save
        lda #1
        sta ba_on               ; a rect is pending erase
        sta ba_live             ; ...and the ball is on screen
        rts
@gone:  lda #0                  ; off screen: stop the stamps, but leave
        sta ba_live             ; ba_on alone: the last drawn rect still
        rts                     ; has to be put back once

; ball_stamp - a white two-by-two dot, the size of the original's.
ball_stamp:
        lda #<buf_ball
        sta bufptr
        lda #>buf_ball
        sta bufptr+1
        lda ba_bl
        sta spy
        lda ba_bc               ; the ball's own byte column, not whoever
        sta spx                 ; stamped last - a stale spx paints outside
        lda ball_sx             ; the saved rect and never gets erased
        jsr split_x
        sta tmp2
        asl a
        asl a                   ; four bytes per shift
        clc
        adc #<ball_spr
        sta sptr
        lda #>ball_spr
        adc #0
        sta sptr+1
        lda #2
        sta cnt
@row:   lda spy
        ldx spx
        jsr blit_setup
        ldy #0
        lda (sptr),y            ; pure replace, as in ply_stamp: the dot
        sta (dptr),y            ; must survive over attribute cells too
        ldy #1
        lda (sptr),y
        sta (dptr),y
        ldy #0                  ; the saved court bytes, twelve pixels right
        lda (bufptr),y
        ldy #2
        sta (dptr),y
        ldy #1
        lda (bufptr),y
        ldy #3
        sta (dptr),y
        inc spy
        clc
        lda dptr
        adc #SCR_BYTES
        sta dptr
        bcc @nc
        inc dptr+1
@nc:    dec cnt
        bne @row
        rts

; shadow_save - the one cell directly under the ball, on the ground line.
shadow_save:
        lda ba_bc
        beq @done
        sta spx
        sta sh_bc               ; register the cell, or the erase re-derives
        lda #1                  ; it from a ground_row the next frame's
        sta spw                 ; projection has already moved
        sta sph
        lda #<buf_sh
        sta bufptr
        lda #>buf_sh
        sta bufptr+1
        lda ground_row
        sta spy
        sta sh_bl
        jmp rect_save
@done:  rts

; shadow_stamp - a white dash over the shadow cell, like the original's dot.
shadow_stamp:
        lda ba_bc
        beq @done
        sta spx
        lda ground_row
        sta spy
        lda spy                 ; blit_setup wants the line in A and the
        ldx spx                 ; byte column in X: it never reads spx/spy
        jsr blit_setup
        lda #$7E
        ldy #0
        sta (dptr),y
@done:  rts

; draw_sprites - project, save the rects of the players, the ball and the
; shadow (all from a screen nothing has touched yet this frame), then stamp
; the figures in the same order.  erase_all restores the rects in reverse.
;
; erase_all runs at entry, not only in the rally: every state that draws
; between points (serve placement, point and set pauses) re-stamps the
; standing figures every frame, and shifting the placement or the pose
; without first restoring the cells ors the new stamp over the old one -
; the ghosts the court showed after a few points.  A second erase in a
; frame is a no-op: erase_all clears the flags it uses.
draw_sprites:
        jsr erase_all
        jsr proj_players
        jsr proj_ball
        ; ---- movement flags, you ----
        lda p0_sx
        cmp p0_savx
        bne @mv0
        lda p0_sy
        cmp p0_savy
        bne @mv0
        lda #0
        sta mv_s
        jmp @f0
@mv0:   lda #1
        sta mv_s
@f0:    lda p0_sx
        sta p0_savx
        lda p0_sy
        sta p0_savy
        ; ---- movement flags, the computer ----
        lda p1_sx
        cmp p1_savx
        bne @mv1
        lda p1_sy
        cmp p1_savy
        bne @mv1
        lda #0
        sta mv_s
        jmp @f1
@mv1:   lda #1
        sta mv_s
@f1:    lda p1_sx
        sta p1_savx
        lda p1_sy
        sta p1_savy
        ; ---- saves ----
        lda #0
        sta who_s
        lda #<buf_p0
        sta bufptr
        lda #>buf_p0
        sta bufptr+1
        lda p0_sx
        ldy p0_sy
        jsr ply_save
        lda #1
        sta who_s
        lda #<buf_p1
        sta bufptr
        lda #>buf_p1
        sta bufptr+1
        lda p1_sx
        ldy p1_sy
        jsr ply_save
        lda ball_sx
        ldy ball_sy
        jsr ball_save
        lda ba_live
        beq @ply                ; ball not on screen this frame
        jsr shadow_save
@ply:   ; the figures stamp whatever the ball is doing: gating them off
        ; the ball's flag made the players flicker every dead-ball frame
        lda #0
        sta who_s
        lda #<buf_p0
        sta bufptr
        lda #>buf_p0
        sta bufptr+1
        jsr ply_stamp
        lda #1
        sta who_s
        lda #<buf_p1
        sta bufptr
        lda #>buf_p1
        sta bufptr+1
        jsr ply_stamp
        lda #1
        sta p0_on
        sta p1_on
        lda ba_live
        beq @done               ; the ball only stamps while on screen
        jsr ball_stamp
        jsr shadow_stamp
@done:  rts

; xtab_lookup - A = pixel column -> A = byte column, clamped to 0..39
xtab_lookup:
        cmp #240
        bcc @ok
        lda #239
@ok:    tax
        lda xtab,x
        rts

; ---------------------------------------------------------------------------
; st_title - the attract screen.  Left and right change the value under the
; selected heading (up and down swap the heading), so SPACE starts a match.
; Left alone for two seconds it starts a demo rally.
st_title:
        inc tick
        lda kflags
        and #KF_FIRE
        beq @arrows
        lda prevf
        bne @attract
        lda #0
        sta demo                ; the player has taken over
        lda #SFX_BLIP
        jsr sfx_play
        jmp @start
@arrows:
        lda kflags
        sta prevk
        and #KF_ARROWS
        beq @attract
        sta tmp1
        lda prevk
        and #KF_ARROWS
        bne @done               ; no repeat until the arrows are released
        lda tmp1
        and #KF_UP+KF_DOWN
        beq @lr
        lda cur_w               ; up and down swap the selected heading
        eor #1
        sta cur_w
        lda #SFX_BLIP
        jsr sfx_play
        jmp @done
@lr:    lda cur_w
        beq @surf
        jsr op_step
        jmp @blip
@surf:  jsr surf_step
@blip:  lda #SFX_BLIP
        jsr sfx_play
        jmp @done
@attract:
        lda tick
        cmp #100                ; two seconds of attract, then a demo rally
        bcc @done
        lda #1
        sta demo
@start: lda #ST_SERVE
        sta st
        lda #0
        sta tick
        lda #1
        jsr msg_put
        jsr draw_sprites
@done:  lda kflags
        sta prevf
        rts

; title_menu - print the title row and the two choice rows (there are no
; numbers to redraw: the menu is text and the maria writes it over itself)
title_menu:
        jsr text_clear
        lda #<m0
        sta txtptr
        lda #>m0
        sta txtptr+1
        ldx #0
        ldy #0
        jsr text_str
        lda #<t_surf
        sta txtptr
        lda #>t_surf
        sta txtptr+1
        ldx #1
        ldy #0
        jsr text_str
        ldx surface
        lda sf_lo,x
        sta txtptr
        lda sf_hi,x
        sta txtptr+1
        ldx #1
        ldy #9
        jsr text_str
        lda #<t_oppt
        sta txtptr
        lda #>t_oppt
        sta txtptr+1
        ldx #1
        ldy #17
        jsr text_str
        ldx opp
        lda op_lo,x
        sta txtptr
        lda op_hi,x
        sta txtptr+1
        ldx #1
        ldy #27
        jsr text_str
        lda #<m13
        sta txtptr
        lda #>m13
        sta txtptr+1
        ldx #2
        ldy #0
        jmp text_str

; surf_step - left or right while SURFACE: is selected
surf_step:
        lda kflags
        and #KF_LEFT
        beq @plus
        dec surface
        bpl @plus
        lda #2
        sta surface
@plus:  lda kflags
        and #KF_RIGHT
        beq @done
        inc surface
        lda surface
        cmp #3
        bcc @done
        lda #0
        sta surface
@done:  jsr apply_surf
        jsr title_menu
        rts

; op_step - left or right while OPPONENT: is selected
op_step:
        lda kflags
        and #KF_LEFT
        beq @plus
        dec opp
        bpl @plus
        lda #2
        sta opp
@plus:  lda kflags
        and #KF_RIGHT
        beq @done
        inc opp
        lda opp
        cmp #3
        bcc @done
        lda #0
        sta opp
@done:  jsr apply_opp
        jsr title_menu
        rts

; ---------------------------------------------------------------------------
; sfx_play - A = sound id.  Rewinds the sequencer over that sound's step
; list; whatever was playing is cut off.
sfx_play:
        tax
        lda snd_lo,x
        sta snd_ptr
        lda snd_hi,x
        sta snd_ptr+1
        lda #0
        sta snd_tmr
        rts

; sfx_tick - one frame of sequencer.  Each step is four bytes: mixer, tone
; period's low byte, coarse nibble plus volume in its high one, and hold.
sfx_tick:
        lda snd_ptr
        ora snd_ptr+1
        beq @done               ; nothing is playing
        lda snd_tmr
        beq @next
        dec snd_tmr
        rts
@next:  ldy #3
        lda (snd_ptr),y
        beq @stop               ; a zero hold ends the sound
        sta snd_tmr
        ldy #2
        lda (snd_ptr),y
        sta tmp2
        ldy #1
        lda (snd_ptr),y
        sta tmp1
        lda #0                  ; period, bits 0-7
        ldx tmp1
        jsr ay_set
        lda #1                  ; period bits 8-11
        lda tmp2
        and #$0F
        tax
        lda #1
        jsr ay_set
        lda tmp2
        lsr a
        lsr a
        lsr a
        lsr a
        tax
        lda #8
        jsr ay_set
        ldy #0
        lda (snd_ptr),y
        ora #$C0                ; bits 6/7 of reg 7 are the port direction
        tax                     ; bits: keep port A output or the keyboard
        lda #7                  ; columns stop driving, and no key is ever
        jsr ay_set              ; read again
        clc
        lda snd_ptr
        adc #4
        sta snd_ptr
        bcc @nc
        inc snd_ptr+1
@nc:    rts
@stop:  lda #0                  ; silence: channel volume zero
        ldx #0
        jsr ay_set
        lda #0
        sta snd_ptr
        sta snd_ptr+1
        rts
@done:  rts

; apply_surf - colour the court by the chosen surface: reload the stroke
; speed and the bounce-reduction constant
apply_surf:
        ldx surface
        lda spd_lo,x
        sta speed_y
        lda spd_hi,x
        sta speed_y+1
        lda bnc_k,x
        sta bounce_k
        rts

; apply_opp - load the computer's shuffle speed and reach
apply_opp:
        ldx opp
        lda ai_spd,x
        sta ai_speed
        lda ai_rch,x
        sta reach_a
        rts

; ---------------------------------------------------------------------------
; st_serve - the ball is held at the server's baseline until fire is pressed
st_serve:
        jsr erase_all
        lda tick
        bne @nopl
        ; a fresh point: the server starts behind its baseline and the
        ; depth keys are frozen until the ball is struck
        lda #1
        sta p_hold
        lda srv
        bne @cpuh
        lda #120
        sta p0y
        jmp @nopl
@cpuh:  lda #20
        sta p1y
@nopl:  jsr move_you
        jsr move_ai
        lda srv
        beq @you
        lda #128
        sta bxh
        lda #0
        sta bxl
        lda p1y
        sta byh
        lda #0
        sta byl
        jsr held_z              ; the held ball bobs at racket height
        lda #0
        sta bzl
        inc tick
        lda tick
        cmp #50
        bcc @draw
        jsr do_serve
        jmp @draw
@you:   lda #128
        sta bxh
        lda #0
        sta bxl
        lda p0y
        sta byh
        lda #0
        sta byl
        jsr held_z              ; the held ball bobs at racket height
        lda #0
        sta bzl
        inc tick
        lda demo
        beq @manual
        lda tick
        cmp #60
        bcc @draw
        jsr do_serve
        jmp @draw
@manual:
        lda kflags
        and #KF_FIRE
        beq @draw
        lda prevf
        bne @draw
        jsr do_serve
@draw:  lda kflags
        sta prevf
        jsr draw_sprites
        rts

; held_z - A = the height for the ball waiting in the server's hand: a
; gentle bob at racket height, so the mark next to the player moves like the
; original's waiting ball instead of hanging frozen at head height.
held_z:
        lda tick
        lsr a
        lsr a
        and #3
        tay
        lda bob_z,y
        sta bzh
        rts

bob_z:  .byte 8,10,12,10

; do_serve - put the ball in play from the server's side: depth aims one
; notch per serve from a free-running frame counter, so roughly one serve in
; four lands out of the service box; the racket marks the rest of the aim.
do_serve:
        lda #0
        sta ba_live             ; stamps off; ba_on survives so the last
        sta vxl                 ; drawn rect is still erased once
        sta vxh
        sta p_hold              ; the ball is struck: the depth keys are live
        sta bounced
        ldx surface
        lda spd_lo,x            ; the pace starts from the surface base
        sta speed_y
        lda spd_hi,x
        sta speed_y+1
        lda srv
        sta last_hit
        lda tick
        sta ht_tick             ; the server shows the swing pose
        lda frame_count
        lsr a
        lsr a
        and #3                  ; a new depth step every four frames
        clc
        ldx srv
        beq @you2
        ora #$04                ; index into the serve table, four per side
@you2:  tax
        lda serve_lo,x
        sta vyl
        lda serve_hi,x
        sta vyh
        lda srv
        bne @cpu2
        lda #0                  ; negate it for you, who serves downwards
        sec
        sbc vyl
        sta vyl
        lda #0
        sbc vyh
        sta vyh
@cpu2:  ; the racket aims the serve into this point's service box
        lda frame_count
        lsr a
        lsr a
        lsr a
        lsr a
        and #3
        asl a
        asl a
        asl a
        clc
        adc #16                 ; aim 16..40 units from the service tee
                                ; (xvel_from_offset times it by 4)
        ldx serve_side
        beq @left
        jsr xvel_from_offset
        jmp @up
@left:  eor #$FF
        clc
        adc #1                  ; and to the left for the other box
        jsr xvel_from_offset
@up:    lda #18                 ; strike at the release height this arc
        sta bzh                 ; was tuned for, so the serve clears the
        lda #0                  ; net (held_z's bob is racket height)
        sta bzl
        lda #<SERVE_VZ
        sta vzl
        lda #>SERVE_VZ
        sta vzh
        lda #1
        sta serve_in
        lda #ST_RALLY
        sta st
        lda #0
        sta tick
        lda #SFX_SERVE
        jsr sfx_play
        lda #12                 ; an empty rally message
        jmp msg_put

; serve_box_check - called just as the serve bounces.  Legal: the ball is
; inside the service box this side aims at, on the right half of the court.
; C set means the serve is good.
serve_box_check:
        lda srv
        bne @near
        lda byh                 ; your serve: the far box, depth 30..64 units
        cmp #SERV_FAR+1
        bcc @bad
        cmp #NET_DEPTH+1
        bcs @bad
        jmp @x
@near:  lda byh                 ; the computer's: depth 64..98 units
        cmp #NET_DEPTH
        bcc @bad
        cmp #SERV_NEAR+1
        bcs @bad
@x:     lda bxh
        cmp #64
        bcc @bad
        cmp #193
        bcs @bad
        lda serve_side
        beq @left
        lda bxh
        cmp #128                ; serving right: it must not land left
        bcc @bad
@ok:    sec
        rts
@left:  lda bxh
        cmp #129                ; serving left: it must not land right
        bcs @bad
        sec
        rts
@bad:   clc
        rts

; do_fault - the serve did not land in the service box.  One fault: serve
; again; two in a row: the point is the receiver's.
do_fault:
        lda #0
        sta serve_in
        inc faults
        lda faults
        cmp #2
        bcc @again
        lda srv
        eor #1                  ; double fault: the receiver's point
        jsr award
        lda #7
        jmp msg_put             ; shows where the point went
@again: lda #SFX_FAULT
        jsr sfx_play
        lda #ST_SERVE
        sta st
        lda #0
        sta tick
        lda #6
        jmp msg_put

; ---------------------------------------------------------------------------
; st_rally - play the point out
st_rally:
        jsr erase_all
        jsr move_you
        jsr move_ai
        jsr ball_step
        jsr hit_test
        jsr check_out
        jsr draw_sprites
        rts

; ---------------------------------------------------------------------------
; move_you - arrows move you around the near half
move_you:
        lda demo
        beq @keys
        ; demo: shuffle across after the ball, and hold a row just behind
        ; it, so the machine player moves on both axes
        lda bxh
        sta tmp1
        lda p0x
        cmp tmp1
        beq @dd
        bcc @dright
        sec
        sbc #PL_SPEED
        cmp #72
        bcs @dl
        lda #72
@dl:    sta p0x
        jmp @dd
@dright:clc
        adc #PL_SPEED
        cmp #185
        bcc @dr
        lda #184
@dr:    sta p0x
@dd:    lda st
        cmp #ST_RALLY
        bne @nodd
        lda byh                 ; depth: stand a touch behind the ball
        clc
        adc #4
        cmp #123
        bcc @dd1
        lda #123
@dd1:   cmp #92
        bcs @dd2
        lda #92
@dd2:   sta tmp1
        lda p0y
        cmp tmp1
        beq @done
        bcc @ddy
        sec
        sbc #PL_SPEED
        cmp #92
        bcs @dd3
        lda #92
@dd3:   sta p0y
        jmp @done
@ddy:   clc
        adc #PL_SPEED
        cmp #123
        bcc @dd4
        lda #123
@dd4:   sta p0y
        jmp @done
@nodd:  jmp @done
@keys:  lda kflags
        and #KF_LEFT
        beq @right
        lda p0x
        sec
        sbc #PL_SPEED
        cmp #72
        bcs @sx
        lda #72
@sx:    sta p0x
@right: lda kflags
        and #KF_RIGHT
        beq @up
        lda p0x
        clc
        adc #PL_SPEED
        cmp #185
        bcc @sx2
        lda #184
@sx2:   sta p0x
@up:    lda kflags
        and #KF_UP
        beq @down
        lda p_hold
        bne @down               ; the serve wait freezes the depth keys
        lda p0y
        sec
        sbc #PL_SPEED
        cmp #66
        bcs @sy
        lda #66
@sy:    sta p0y
@down:  lda kflags
        and #KF_DOWN
        beq @done
        lda p_hold
        bne @done
        lda p0y
        clc
        adc #PL_SPEED
        cmp #123
        bcc @sy2
        lda #123
@sy2:   sta p0y
@done:  rts

; ---------------------------------------------------------------------------
; move_ai - the computer watches the ball: it shuffles across its baseline
; and steps up to meet the ball once it has bounced on its half
move_ai:
        ; the x target: the ball while it is on this half, the middle of
        ; the baseline while it is yours
        lda byh
        cmp #NET_DEPTH
        bcc @track
        lda #128
        sta tmp1
        jmp @go
@track: lda bxh
        sta tmp1
@go:    lda p1x
        cmp tmp1
        beq @dy1
        bcc @right
        sec
        sbc ai_speed
        cmp #72
        bcs @l
        lda #72
@l:     sta p1x
        jmp @dy1
@right: clc
        adc ai_speed
        cmp #185
        bcc @r
        lda #184
@r:     sta p1x
        ; depth: home to the baseline by default; when the ball has
        ; bounced on this half, step up to stand a little behind it
@dy1:   lda p_hold
        bne @dhome
        lda bounced
        beq @dhome
        lda st
        cmp #ST_RALLY
        bne @dhome
        lda byh
        cmp #NET_DEPTH
        bcc @dup
@dhome: lda #20
        jmp @dset
@dup:   lda byh
        clc
        adc #6
        cmp #58
        bcc @dup1
        lda #58
@dup1:  cmp #12
        bcs @dset
        lda #12
@dset:  sta tmp1
@dgo:   lda p1y
        cmp tmp1
        beq @done
        bcc @dn
        sec
        sbc ai_speed
        cmp tmp1
        bcs @ds1
        lda tmp1
@ds1:   sta p1y
        jmp @done
@dn:    clc
        adc ai_speed
        cmp tmp1
        bcc @ds2
        lda tmp1
@ds2:   sta p1y
@done:  rts

; ---------------------------------------------------------------------------
; ball_step - gravity, the bounce and the three integrations
ball_step:
        lda byh
        sta prev_by
        ; vz -= gravity
        sec
        lda vzl
        sbc #<GRAV
        sta vzl
        lda vzh
        sbc #>GRAV
        sta vzh
        ; x += vx
        clc
        lda bxl
        adc vxl
        sta bxl
        lda bxh
        adc vxh
        sta bxh
        ; y += vy
        clc
        lda byl
        adc vyl
        sta byl
        lda byh
        adc vyh
        sta byh
        ; z += vz
        clc
        lda bzl
        adc vzl
        sta bzl
        lda bzh
        adc vzh
        sta bzh
        ; landed?
        lda bzh
        bpl @netcheck
        lda #0
        sta bzh
        sta bzl
        lda #1
        sta bounced             ; the ball has pitched: receivers may step up
        lda serve_in
        beq @kick               ; not a serve: every bounce is legal
        jsr serve_box_check     ; a serve has bounced: was it in the box?
        bcc @fault
        lda #0                  ; it was: the ball now plays like any other
        sta serve_in
@kick:  ; vz = -vz * (1 - 2^-k), negated first so the shifts can be logical
        lda #0
        sec
        sbc vzl
        sta vzl
        lda #0
        sbc vzh
        sta vzh                 ; vz = -vz, now rising
        lda vzl
        sta tmp1
        lda vzh
        sta tmp2
        ldx bounce_k
@rest:  lsr tmp2
        ror tmp1
        dex
        bne @rest               ; vz / 2^k
        lda vzl
        sec
        sbc tmp1
        sta vzl
        lda vzh
        sbc tmp2
        sta vzh                 ; vz - vz/2^k
        ; the kick has to be worth a thump; a dying ball gets none
        lda vzh
        bne @thump
        lda vzl
        cmp #48
        bcc @netcheck
@thump: lda #SFX_BOUNCE
        jsr sfx_play
        jmp @netcheck
@fault: jmp do_fault
@netcheck:
        ; did the ball cross the net plane below the top of the net?
        lda prev_by
        sec
        sbc #NET_DEPTH
        sta tmp1                ; one side of the eor, relative to the plane
        lda byh
        sec
        sbc #NET_DEPTH
        eor tmp1
        bmi @cross              ; the signs differ: it crossed the plane
        bpl @done
@cross: lda bzh
        cmp #NET_TOP
        bcs @done
        lda serve_in
        bne @srvnet
        lda #SFX_NET
        jsr sfx_play
        lda #1
        sta ptwhy
        lda last_hit
        eor #1
        jmp award               ; whoever struck it into the net loses
@srvnet:
        jmp do_fault            ; a serve into the net is a fault
@done:  rts

; ---------------------------------------------------------------------------
; hit_test - can whoever the ball is coming to reach it?
hit_test:
        lda st
        cmp #ST_RALLY
        bne @done               ; the point is already decided: hands off
        lda last_hit
        beq @cpu
        ; the ball is coming to you
        lda byh
        cmp p0y
        bcc @done               ; still short of you
        jsr reach_you
        bcc @noyou
        jsr hit_you
        rts
@noyou: lda bzh                 ; a ball crossing your row still in the air
        cmp #HIT_Z              ; is not lost: it can come down behind you
        bcc @miss_you
        rts
@miss_you:
        lda #1
        jmp award
@cpu:   lda byh
        cmp p1y
        bcs @done               ; still short of the computer
        jsr reach_cpu
        bcc @nocpu
        jsr hit_cpu
        rts
@nocpu: lda bzh                 ; the same grace on the computer's side
        cmp #HIT_Z
        bcc @miss_cpu
        rts
@miss_cpu:
        lda #0
        jmp award
@done:  rts

; reach_you - C set when you are close enough and the ball is low enough
reach_you:
        lda byh                 ; the row has to be near yours: the reach
        sec                     ; is straight-line, not across the court
        sbc p0y
        bcs @ry1
        eor #$FF
        clc
        adc #1
@ry1:   cmp #REACH_ROW
        bcc @ry2
        clc
        rts
@ry2:   lda bzh
        cmp #HIT_Z
        bcs @no
        lda bxh
        sec
        sbc p0x
        bcs @p
        eor #$FF
        clc
        adc #1
@p:     cmp #REACH_P
        bcc @yes
@no:    clc
        rts
@yes:   sec
        rts

reach_cpu:
        lda byh                 ; the same row window on the near side
        sec
        sbc p1y
        bcs @rc1
        eor #$FF
        clc
        adc #1
@rc1:   cmp #REACH_ROW
        bcc @rc2
        clc
        rts
@rc2:   lda bzh
        cmp #HIT_Z
        bcs @no
        lda bxh
        sec
        sbc p1x
        bcs @p
        eor #$FF
        clc
        adc #1
@p:     cmp reach_a
        bcc @yes
@no:    clc
        rts
@yes:   sec
        rts

; hit_you - send the ball back towards the far court
hit_you:
        lda #0
        sta last_hit
        lda tick
        sta ht_tick             ; show the swing pose for a dozen frames
        jsr lob_shot
        jsr aim_y_far
        lda #128
        sec
        sbc p1x                 ; aim into the court the computer has left
        jsr aim_spread
        jsr ramp_speed
        jsr xvel_from_offset
        jmp thwack

hit_cpu:
        lda #1
        sta last_hit
        lda tick
        sta ht_tick             ; show the swing pose for a dozen frames
        lda #<HIT_VZ
        sta vzl
        lda #>HIT_VZ
        sta vzh
        jsr aim_y_near
        lda #128
        sec
        sbc p0x                 ; and back the other way
        jsr aim_spread
        jsr ramp_speed
        jsr xvel_from_offset
        jmp thwack

; ramp_speed - every stroke adds a little pace to speed_y, so real rallies
; quicken until someone finally cannot get to the ball.  Without this the
; rally settles into a becalmed centre exchange that never ends.
ramp_speed:
        clc
        lda speed_y
        adc #RAMP_STEP          ; low half: 1 unit = 1/256 px/frame
        sta speed_y
        lda speed_y+1
        adc #0                  ; carry into the high byte
        cmp #RAMP_CAP_HI
        bcc @capdone
        sta speed_y+1
        lda #0
        sta speed_y
@capdone:
        rts

; aim_spread - A = signed aim offset from the centre line.  Adds a
; frame-dependent twist so that two shots never land on the same spot: the
; alternative is a rally that collapses into an endless becalmed centre
; exchange, with both players parked on the middle line.
aim_spread:
        sta tmp1
        lda frame_count
        lsr a
        lsr a
        lsr a
        and #7                  ; changes every eight frames
        tay
        lda spread8,y
        clc
        adc tmp1
        rts

; lob_shot - fire gives a higher ball (a lob), otherwise a drive
lob_shot:
        lda kflags
        and #KF_FIRE
        beq @drive
        lda #<(HIT_VZ + 200)
        sta vzl
        lda #>(HIT_VZ + 200)
        sta vzh
        rts
@drive: lda #<HIT_VZ
        sta vzl
        lda #>HIT_VZ
        sta vzh
        rts

; aim_y_far - the ball travels towards the far baseline
aim_y_far:
        lda #0                  ; negate speed_y
        sec
        sbc speed_y
        sta vyl
        lda #0
        sbc speed_y+1
        sta vyh
        rts

; aim_y_near - the ball travels towards you
aim_y_near:
        lda speed_y
        sta vyl
        lda speed_y+1
        sta vyh
        rts

; xvel_from_offset - A = signed offset from the centre line -> vx
xvel_from_offset:
        sta mt_a
        lda #0
        sta mt_sign
        lda mt_a
        bpl @p
        eor #$FF
        clc
        adc #1
        sta mt_a
        lda #$80
        sta mt_sign
@p:     lda mt_a                 ; up to 56 units from the middle
        sta vxl
        lda #0
        sta vxh
        asl vxl
        rol vxh
        asl vxl
        rol vxh                 ; vx = offset * 4, in 8.8
        lda mt_sign
        bpl @done
        lda #0
        sec
        sbc vxl
        sta vxl
        lda #0
        sbc vxh
        sta vxh
@done:  rts

; thwack - the ball leaves the racket just off the ground
thwack:
        lda #6
        sta bzh
        lda #0
        sta bzl
        lda #SFX_HIT
        jmp sfx_play

; ---------------------------------------------------------------------------
; check_out - has the ball left the court?
check_out:
        lda st
        cmp #ST_RALLY
        bne @done               ; the point is already decided
        ; past a baseline?
        lda byh
        bmi @far
        cmp #124
        bcs @near
        ; past a sideline?
        lda bxh
        cmp #64
        bcc @side
        cmp #192
        bcc @done
@srf:   jmp do_fault            ; the serve left the court before it landed
@far:   lda serve_in
        bne @srf                ; a serve that flies past the far line: fault
        lda last_hit
        eor #1
        jmp award
@near:  lda serve_in
        bne @srf                ; or past the near line
        lda last_hit
        jmp award
@side:  lda serve_in
        bne @srf                ; or a sideline
        lda last_hit
        eor #1
        jmp award
@done:  rts

; ---------------------------------------------------------------------------
; award - A = who wins the point (0 = you, 1 = the computer)
award:
        sta tmp1
        lda #ST_POINT
        sta st
        lda #0
        sta tick
        sta serve_in
        lda ptwhy               ; the point ended at the net: say whose fault
        bne @net
        lda #2                  ; message 2 is "point to you"
        ldx tmp1
        beq @m
        lda #3
@m:     jsr msg_put
        jmp @snd
@net:   ldx tmp1                ; the winner is the player who did not strike it
        beq @n9
        lda #8                  ; YOU HIT THE NET
        jmp @pub
@n9:    lda #9                  ; THE COMPUTER HITS THE NET
@pub:   jsr msg_put
@snd:   lda #0
        sta ptwhy
        lda tmp1
        beq @w2
        lda #SFX_LOSE
        jsr sfx_play
        jmp add_point
@w2:    lda #SFX_WIN
        jsr sfx_play
        jmp add_point

; ---------------------------------------------------------------------------
; add_point - A = 0 or 1, the winner of the point
add_point:
        sta cur_w
        eor #1
        sta cur_l
        ldx cur_l
        lda pts,x
        cmp #4
        bne @noadv
        lda #3
        sta pts,x               ; advantage lost: back to deuce
        jmp @done
@noadv: ldx cur_w
        lda pts,x
        cmp #4
        beq @game
        clc
        adc #1
        sta pts,x
        cmp #4
        bne @done
        ldx cur_l
        lda pts,x
        cmp #3
        beq @done               ; advantage
@game:  jsr win_game
@done:  jmp hud_draw

; win_game - the winner of the point takes the game
win_game:
        ldx cur_w
        inc games,x
        lda #0
        sta pts
        sta pts+1
        lda srv
        eor #1
        sta srv
        lda serve_side
        eor #1
        sta serve_side          ; tennis: you change ends every game
        ldx cur_w
        lda games,x
        cmp #6
        bcc @game
        ldx cur_l
        lda games,x
        sta tmp1
        ldx cur_w
        lda games,x
        sec
        sbc tmp1
        cmp #2
        bcc @game
        ; six games, and two ahead: that is the set
        ldx cur_w
        inc sets,x
        lda #0
        sta games
        sta games+1
        lda #SFX_SET
        jsr sfx_play
        ldx cur_w
        lda sets,x
        cmp #SET_WINS
        bcc @set
        lda #1                  ; two sets: the match is over
        sta over
        rts
@set:   lda #1
        sta set_over            ; st_point shows the set banner, st_set serves
        rts
@game:  lda #SFX_GAME
        jsr sfx_play
        rts

; ---------------------------------------------------------------------------
; st_point - a short pause on the point, then the next serve
st_point:
        jsr draw_sprites
        inc tick
        lda tick
        cmp #70
        bcc @done
        lda set_over            ; a set was taken: show it, then serve again
        beq @overchk
        lda #ST_SET
        sta st
        lda #0
        sta tick
        ldx #0                  ; who took the set?
        lda sets
        bne @sw
        ldx #1
@sw:    lda #10
        cpx #0
        beq @sm
        lda #11
@sm:    jsr msg_put
        lda #0
        sta prevf
        rts
@overchk:
        lda over
        beq @next
        lda #ST_OVER
        sta st
        lda #0
        sta tick
        lda #4
        ldx sets
        beq @mw
        lda #5
@mw:    jsr msg_put
        lda #SFX_MATCH          ; a match-winning fanfare (or a groan)
        ldx sets
        beq @mfx
        lda #SFX_LOSM
@mfx:   jsr sfx_play
        lda #0
        sta prevf
        rts
@next:  lda #0
        sta faults
        lda serve_side          ; tennis: courts alternate every point
        eor #1
        sta serve_side
        lda #ST_SERVE
        sta st
        lda #0
        sta tick
        lda #1
        jmp msg_put
@done:  rts

; ---------------------------------------------------------------------------
; st_set - pause on the set-won message, then a fresh set
st_set:
        jsr draw_sprites
        inc tick
        lda tick
        cmp #140
        bcc @done
        lda #0
        sta set_over
        lda #ST_SERVE
        sta st
        lda #0
        sta tick
        sta prevf
        lda #1
        jsr msg_put
        jsr draw_sprites
@done:  rts

; ---------------------------------------------------------------------------
; st_over - the match is decided; fire starts another
st_over:
        lda demo
        beq @manual
        inc tick
        lda tick
        cmp #150
        bcc @keep
        jsr new_match
        lda #ST_SERVE
        sta st
        lda #0
        sta tick
        lda #1
        jsr msg_put
        jmp @keep
@manual:
        lda kflags
        and #KF_FIRE
        beq @keep
        lda prevf
        bne @keep
        lda #0
        sta demo                ; fire from the result screen: back to titles
        jsr new_match
        jsr title_menu
        lda #ST_TITLE
        sta st
        lda #0
        sta tick
@keep:  lda kflags
        sta prevf
        rts

; ---------------------------------------------------------------------------
        .rodata

; the players: 7 pixels wide by 14 tall, three poses (feet apart, mid-stride,
; swing with the arm and racket up) x six pixel shifts.  Each pair of bytes
; is the value stamped over the two screen cells: the figure's ink pixels in
; white, so the picture keeps ordinary write semantics (no attribute work;
; every other line in the picture, so no attribute surgery is needed and the
; row's colour stream stays exactly as the court drew it.
ply_f0:
        .byte $4E,$40,$4E,$40,$4E,$40,$5F,$40,$5F,$40,$5F,$40,$5F,$40,$4E,$40,$5B,$40,$5B,$40,$5B,$40,$5B,$40,$5B,$40,$71,$60
        .byte $47,$40,$47,$40,$47,$40,$4F,$60,$4F,$60,$4F,$60,$4F,$60,$47,$40,$4D,$60,$4D,$60,$4D,$60,$4D,$60,$4D,$60,$58,$70
        .byte $43,$60,$43,$60,$43,$60,$47,$70,$47,$70,$47,$70,$47,$70,$43,$60,$46,$70,$46,$70,$46,$70,$46,$70,$46,$70,$4C,$58
        .byte $41,$70,$41,$70,$41,$70,$43,$78,$43,$78,$43,$78,$43,$78,$41,$70,$43,$58,$43,$58,$43,$58,$43,$58,$43,$58,$46,$4C
        .byte $40,$78,$40,$78,$40,$78,$41,$7C,$41,$7C,$41,$7C,$41,$7C,$40,$78,$41,$6C,$41,$6C,$41,$6C,$41,$6C,$41,$6C,$43,$46
        .byte $40,$5C,$40,$5C,$40,$5C,$40,$7E,$40,$7E,$40,$7E,$40,$7E,$40,$5C,$40,$76,$40,$76,$40,$76,$40,$76,$40,$76,$41,$63
ply_f1:
        .byte $4E,$40,$4E,$40,$4E,$40,$5F,$40,$5F,$40,$5F,$40,$5F,$40,$4E,$40,$5B,$40,$59,$60,$59,$60,$49,$60,$49,$60,$4C,$60
        .byte $47,$40,$47,$40,$47,$40,$4F,$60,$4F,$60,$4F,$60,$4F,$60,$47,$40,$4D,$60,$4C,$70,$4C,$70,$44,$70,$44,$70,$46,$50
        .byte $43,$60,$43,$60,$43,$60,$47,$70,$47,$70,$47,$70,$47,$70,$43,$60,$46,$70,$46,$58,$46,$58,$42,$58,$42,$58,$43,$48
        .byte $41,$70,$41,$70,$41,$70,$43,$78,$43,$78,$43,$78,$43,$78,$41,$70,$43,$58,$43,$4C,$43,$4C,$41,$4C,$41,$4C,$41,$64
        .byte $40,$78,$40,$78,$40,$78,$41,$7C,$41,$7C,$41,$7C,$41,$7C,$40,$78,$41,$6C,$41,$66,$41,$66,$40,$66,$40,$66,$40,$72
        .byte $40,$5C,$40,$5C,$40,$5C,$40,$7E,$40,$7E,$40,$7E,$40,$7E,$40,$5C,$40,$76,$40,$73,$40,$73,$40,$53,$40,$53,$40,$59
ply_f2:
        .byte $4E,$60,$4E,$60,$4E,$40,$5F,$40,$5F,$40,$5F,$40,$5F,$40,$4E,$40,$4E,$40,$5B,$40,$5B,$40,$5B,$40,$5B,$40,$71,$60
        .byte $47,$50,$47,$50,$47,$40,$4F,$60,$4F,$60,$4F,$60,$4F,$60,$47,$40,$47,$40,$4D,$60,$4D,$60,$4D,$60,$4D,$60,$58,$70
        .byte $43,$68,$43,$68,$43,$60,$47,$70,$47,$70,$47,$70,$47,$70,$43,$60,$43,$60,$46,$70,$46,$70,$46,$70,$46,$70,$4C,$58
        .byte $41,$74,$41,$74,$41,$70,$43,$78,$43,$78,$43,$78,$43,$78,$41,$70,$41,$70,$43,$58,$43,$58,$43,$58,$43,$58,$46,$4C
        .byte $40,$7A,$40,$7A,$40,$78,$41,$7C,$41,$7C,$41,$7C,$41,$7C,$40,$78,$40,$78,$41,$6C,$41,$6C,$41,$6C,$41,$6C,$43,$46
        .byte $40,$5D,$40,$5D,$40,$5C,$40,$7E,$40,$7E,$40,$7E,$40,$7E,$40,$5C,$40,$5C,$40,$76,$40,$76,$40,$76,$40,$76,$41,$63

; the ball: a white two-by-two dot, the same footprint as the font's full
; stop, pre-shifted zero to five pixels; each shift packs [b0 b1] x 2 rows
ball_spr:
        .byte $58,$40,$58,$40
        .byte $4C,$40,$4C,$40
        .byte $46,$40,$46,$40
        .byte $43,$40,$43,$40
        .byte $41,$60,$41,$60
        .byte $40,$70,$40,$70

; pose_off - 28 x n as words, n = 0..17 (pixel offset + 6 x pose)
; little-endian, lo then hi, matching pose_pick's lda/increment loads
pose_off:
        .byte $00,$00,$1C,$00,$38,$00,$54,$00,$70,$00,$8C,$00,$A8,$00,$C4,$00
        .byte $E0,$00,$FC,$00,$18,$01,$34,$01,$50,$01,$6C,$01,$88,$01,$A4,$01
        .byte $C0,$01,$DC,$01

t_prev: .byte "PREVIOUS SETS",0
t_name: .byte "YOU",0
t_cols: .byte "SETS GAMES POINTS",0
t_cpu:  .byte "COMPUTER",0

s0:   .byte "0",0
s15:  .byte "15",0
s30:  .byte "30",0
s40:  .byte "40",0
sAD:  .byte "AD",0
pt_lo: .byte <s0,<s15,<s30,<s40,<sAD
pt_hi: .byte >s0,>s15,>s30,>s40,>sAD

m0: .byte "MATCH POINT   PRESS SPACE TO PLAY",0
m1: .byte "SPACE TO SERVE - ARROWS TO MOVE",0
m2: .byte "POINT TO YOU",0
m3: .byte "POINT TO THE COMPUTER",0
m4: .byte "YOU WIN THE MATCH",0
m5: .byte "THE COMPUTER WINS",0
m6: .byte "FAULT - SECOND SERVE",0
m7: .byte "DOUBLE FAULT",0
m8: .byte "YOU HIT THE NET",0
m9: .byte "THE COMPUTER HITS THE NET",0
m10:.byte "YOU WIN THE SET",0
m11:.byte "THE COMPUTER WINS THE SET",0
m12:.byte 0
m13:.byte "ARROWS TO CHOOSE - SPACE TO PLAY",0
msg_lo: .byte <m0,<m1,<m2,<m3,<m4,<m5,<m6,<m7,<m8,<m9,<m10,<m11,<m12,<m13
msg_hi: .byte >m0,>m1,>m2,>m3,>m4,>m5,>m6,>m7,>m8,>m9,>m10,>m11,>m12,>m13

; ---------------------------------------------------------------------------
; sfx - one-shot sounds for the AY channel A.  Each step is four bytes:
; the mixer register value, the tone period's low byte, its coarse byte
; (low nibble) with the volume above it, and the frames to hold.  A zero
; frames byte ends the sound.
snd_lo: .byte <s_bounce,<s_hit,<s_serve,<s_net,<s_fault
        .byte <s_win,<s_lose,<s_game,<s_setw,<s_matchw,<s_losem,<s_blip
snd_hi: .byte >s_bounce,>s_hit,>s_serve,>s_net,>s_fault
        .byte >s_win,>s_lose,>s_game,>s_setw,>s_matchw,>s_losem,>s_blip

s_bounce:                               ; short noise thump and decay
        .byte $F7, 0,   $70, 3
        .byte $F7, 0,   $30, 4
        .byte 0
s_hit:                                  ; sharp tuned pock
        .byte $FE, 96,  $C0, 2
        .byte $FE, 72,  $90, 3
        .byte 0
s_serve:
        .byte $FE, 120, $D0, 2
        .byte $FE, 84,  $A0, 4
        .byte 0
s_net:                                  ; noise plus a low buzz
        .byte $F6, 110, $50, 8
        .byte $F7, 0,   $30, 6
        .byte 0
s_fault:
        .byte $FE, 160, $A0, 6
        .byte $FE, 220, $80, 10
        .byte 0
s_win:
        .byte $FE, 152, $A0, 5
        .byte $FE, 96,  $C0, 14
        .byte 0
s_lose:
        .byte $FE, 128, $A0, 5
        .byte $FE, 200, $80, 14
        .byte 0
s_game:                                 ; three rising notes
        .byte $FE, 152, $A0, 4
        .byte $FE, 120, $B0, 4
        .byte $FE, 96,  $C0, 10
        .byte 0
s_setw:                                 ; four notes
        .byte $FE, 120, $B0, 4
        .byte $FE, 96,  $B0, 4
        .byte $FE, 80,  $C0, 4
        .byte $FE, 64,  $D0, 12
        .byte 0
s_matchw:                               ; five notes, longer finish
        .byte $FE, 152, $C0, 4
        .byte $FE, 120, $C0, 4
        .byte $FE, 96,  $C0, 4
        .byte $FE, 76,  $C0, 4
        .byte $FE, 64,  $D0, 16
        .byte 0
s_losem:                                ; four falling notes
        .byte $FE, 128, $A0, 5
        .byte $FE, 160, $90, 5
        .byte $FE, 200, $80, 5
        .byte $FE, 4,   $71, 16       ; period 260 (coarse 1), volume 7
        .byte 0
s_blip:                                 ; the menu click
        .byte $FE, 220, $80, 3
        .byte 0

; ---------------------------------------------------------------------------
; surface and opponent tuning
;   surface: 0 slow, 1 medium, 2 fast.  The surfaces differ in two ways:
;   the base depth speed of a full stroke, and how much of its speed a
;   bounce keeps (vz' = vz - vz/2^k, so k=1 keeps half, k=3 keeps 7/8).
spd_lo: .byte $C0,$00,$40               ; 448, 512, 576
spd_hi: .byte $01,$02,$02
bnc_k:  .byte 1,2,3
;   opponent: 0 easy, 1 normal, 2 hard.  easy: shuffles 1/side, reach 8;
;   normal: reach 14; hard: tracks at 2/side, reach 18.
ai_spd: .byte 1,1,2
ai_rch: .byte 8,14,18
;   groundstroke aim twist (signed px), picked by the frame counter when the
;   racket meets the ball: keeps shots from always landing in one place
spread8:
        .byte 0,24,$D8,12,0,$E8,40,$EC    ; 0,+24,-40,+12,0,-24,+40,-20

; ---------------------------------------------------------------------------
; serve tuning.  SERVE_VZ = 256 flies SERVE_FR = 45 frames; with vz=256 the
; flight crosses the net at 17px plus grace and lands 448 + vy/16 deep.
;   your serve  (strike from depth 120): vy = 456 + j*24
;   the computer (strike from depth 20): vy = 376 + j*32
;   j in 0..3 steps one notch per serve from the free-running frame
;   counter, so roughly one serve in four lands long and is a fault.
serve_lo:
        .byte $C8,$E0,$F8,$10           ; 456, 480, 504, 528
        .byte $78,$98,$B8,$D8           ; 376, 408, 440, 472
serve_hi:
        .byte $01,$01,$01,$02
        .byte $01,$01,$01,$01

; title menu strings
sf_n0: .byte "SLOW   ",0
sf_n1: .byte "MEDIUM ",0
sf_n2: .byte "FAST   ",0
op_n0: .byte "EASY   ",0
op_n1: .byte "NORMAL ",0
op_n2: .byte "HARD   ",0
sf_lo: .byte <sf_n0,<sf_n1,<sf_n2
sf_hi: .byte >sf_n0,>sf_n1,>sf_n2
op_lo: .byte <op_n0,<op_n1,<op_n2
op_hi: .byte >op_n0,>op_n1,>op_n2
t_surf: .byte "SURFACE:",0
t_oppt: .byte "OPPONENT:",0
