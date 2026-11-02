; zp.inc - zero page variables.
;
; The first block is the contract screen.s and hw.s expect; the second is the
; tennis game's own state.  cc65 reserves $E2-$FB so everything lives below $80.

; general pointers (screen.s / hw.s)
scrptr  = $10
sptr    = $12
dptr    = $14
txtptr  = $16
tptr    = $18

; sprite blit
spx     = $1A                   ; byte column 0..39
spy     = $1B                   ; line 0..199
spw     = $1C                   ; width in bytes
sph     = $1D                   ; height in lines

; scratch
tmp1    = $1E
tmp2    = $1F
tmp3    = $20
tmp4    = $21
tmp5    = $22
tmp6    = $23

; maths
numlo   = $24                   ; 16 bit accumulator
numhi   = $25
cnt     = $26
mulcnt  = $27

; screen.s internal scratch
ra0     = $80
ra1     = $81

; ---------------------------------------------------------------------------
; ball, all 16 bit with 8 bits of fraction (high byte = whole unit).
; x 64..192 is between the sidelines, depth 0 is the far baseline and 255 the
; near one, z is the height in pixels with 0 on the ground.
bxl     = $30
bxh     = $31
byl     = $32
byh     = $33
bzl     = $34
bzh     = $35
vxl     = $36
vxh     = $37
vyl     = $38
vyh     = $39
vzl     = $3A
vzh     = $3B

; ---------------------------------------------------------------------------
; players.  p0x/p1x are court x (64..192), p0y/p1y are depth.
p0x     = $3C
p0y     = $3D
p1x     = $3E
p1y     = $3F

; ---------------------------------------------------------------------------
; match state
st          = $40               ; see the ST_* constants in match.s
tick        = $41               ; frames spent in the current state
last_hit    = $42               ; 0 = you hit last, 1 = computer, 2 = dead ball
pts         = $44               ; 2 bytes: 0,15,30,40 points (4 = advantage)
games       = $46               ; 2 bytes
sets        = $48               ; 2 bytes
srv         = $4A               ; 0 = you serve, 1 = the computer
cur_w       = $4B               ; scratch for add_point / win_game
cur_l       = $4C
msg_id      = $4D
over        = $4E               ; the match has been won
kflags      = $4F               ; keys held this frame, bits KF_*
prevf       = $50               ; fire was held last frame

; scratch for the projection and the sprite buffers
mt_a        = $51
mt_b        = $52
mt_sign     = $53
side_tmp    = $54
ground_row  = $55
half_w      = $56
ball_sx     = $57               ; ball pixel column 0..239
ball_sy     = $58               ; ball line 0..199
p0_sx       = $59
p0_sy       = $5A
p1_sx       = $5B
p1_sy       = $5C
bufptr      = $5D               ; 2 bytes: sprite save buffer
demo        = $5F               ; the attract screen is playing itself

snd_ptr     = $60               ; 2 bytes: into the playing sound's steps
