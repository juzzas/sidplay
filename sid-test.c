//
// Created by justin on 13/07/2021.
//

/*
 * https://www.c64-wiki.com/wiki/SID
 *
 *  0 REM *** C64-WIKI SOUND-DEMO ***
 * 10 S = 54272: W = 17: ON INT(RND(TI)*4)+1 GOTO 12,13,14,15
 * 12 W = 33: GOTO 15
 * 13 W = 65: GOTO 15
 * 14 W = 129
 * 15 POKE S+24,15: POKE S+5,97: POKE S+6,200: POKE S+4,W
 * 16 FOR X = 0 TO 255 STEP (RND(TI)*15)+1
 * 17 POKE S,X :POKE S+1,255-X
 * 18 FOR Y = 0 TO 33: NEXT Y,X
 * 19 FOR X = 0 TO 200: NEXT: POKE S+24,0
 * 20 FOR X = 0 TO 100: NEXT: GOTO 10
 * 21 REM *** ABORT ONLY WITH RUN/STOP ! ***
 */
extern void reset_sid(void);
extern void set_sid_reg(uint8_t reg, uint8_t val);

int main(int argc, char **argv)
{
    uint8_t waveform = 17;

    set_sid_reg(25, 15);
    set_sid_reg(5, 97);
    set_sid_reg(6, 200);

}