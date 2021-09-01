SECTION SID

PUBLIC standalone_sid_file_base
PUBLIC standalone_sid_file_length

standalone_sid_file_base:
               binary "Thing_On_A_Spring.sid"
defc standalone_sid_file_end = $
defc standalone_sid_file_length =standalone_sid_file_end - standalone_sid_file_base

