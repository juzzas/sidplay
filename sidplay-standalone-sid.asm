SECTION SID

PUBLIC standalone_sid_file_base
PUBLIC standalone_sid_file_length

standalone_sid_file_base:
     ;          binary "Thing_On_A_Spring.sid"
     ;          binary "Airwolf_Title.sid"
     ;          binary "R-Type.sid"
     ;          binary "Yie_Ar_Kung_Fu.sid"
     ;          binary "Thundercats.sid"
     ;          binary "Dreams.sid"   ; RSID - not support
               binary "SYS4096.sid"
     ;          binary "Driller.sid"
defc standalone_sid_file_end = $
defc standalone_sid_file_length =standalone_sid_file_end - standalone_sid_file_base

