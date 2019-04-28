; =============================================================================
; 00:1:1600 (LOROM, bank 0)

.include "../include/easyflash.inc"
.include "../include/io.inc"
.include "efs.inc"
.include "../include/exodecrunch.inc"


; jump table vectors must be changed via patch
;
; 6c09: IO_request_disk_id
;     param:
;        A: requested disk id in range 0x01 to 0x08
;     return:
;        C set: disk not inserted
;        C clear: disk inserted
;
; 6c2a: IO_request_disk_char
;     param:
;        A: requested disk id in range 0x41 to 0x48
;     return:
;        C set: disk not inserted
;        C clear: disk inserted
;
; 6c24: IO_load_file
;    param:
;        filename: after return address, null terminated
;        x: 0=return; x=1 jmp 0x0800; x>1 jmp 0xa700
;    return:
;        none
;
; 6c2d: IO_save_file
;    saves a file. parameter list, deletes the file and saves it then
;    param:
;        X: unknown
;        string: (after return address) null terminated filename, prepended with "S:"
;        word: (after return address) address
;        word: (after return address) size
;    return:
;        none
;
; 6c00: IO_read_block
;     param:
;         Y: track of disk
;         X: sector of disk
;         A: destination high address
;     return:
;         none
;
; 6c30: IO_read_block_alt
;     reads a block and the following block to a fixed address (0x7e, 0x7f)
;     param:
;         A: unknown
;         X: unknown
;     return:
;         none
;

; export the entry points of the functions
.export IO_request_disk_id_entry
.export IO_request_disk_char_entry
.export IO_load_file_entry
.export IO_save_file_entry
.export IO_read_block_entry
.export IO_read_block_alt_entry

; imports
.import load_prg
.import load_block
.import load_block_highdestination


;.macro event_before
;    jsr $0126  ; copied from original copy
;.endmacro

;.macro event_after
;    jsr $0129  ; copied from original copy
;.endmacro


.segment "IO_CODE"


    ; --------------------------------------------------------------------
    IO_request_disk_id_entry:
        clc
        adc #$40   ; add 40 to get the character

    ; --------------------------------------------------------------------
    IO_request_disk_char_entry:
        sta requested_disk
        clc        ; disk request always succeeds
        rts

    ; --------------------------------------------------------------------
    ; IO_load_file_entry: load file
    ; filename after return address
    ; x: return mode (0, 1, >1)
    IO_load_file_entry:
        stx requested_loadmode
        pla                            ; load return address to copy opcode
        sta load_file_copyname_address_low
        pla
        sta load_file_copyname_address_high
        inc load_file_copyname_address_low     ; and increase by one
        bne @skip
        inc load_file_copyname_address_high
    @skip:
        ldy #$ff                       ; initialize for copy
    load_file_copyname_address_low = load_file_copyname_address + 1
    load_file_copyname_address_high = load_file_copyname_address + 2
    load_file_copyname:
        iny
    load_file_copyname_address:
        lda $ffff                      ; load
        sta requested_filename, y      ; and store
        beq copydone        
        inc load_file_copyname_address_low
        bne @skip
        inc load_file_copyname_address_high
    @skip:
        jmp load_file_copyname
    copydone:

        ldx #$00
        stx load_block_highdestination ; 0 will load a prg file
        jsr load_file_from_ef          ; load file: X: in file offset

        lda requested_loadmode
        beq load_return
        cmp #$01
        beq load_jumptomain
        jmp $a700  
    load_jumptomain:
        jmp $8000
    load_return:
        lda load_file_copyname_address_high    ; return address on stack
        pha
        lda load_file_copyname_address_low
        pha
        rts
    requested_loadmode:
        .byte $00


    ; --------------------------------------------------------------------
    ; IO_save_file_entry
    ; read parameter from after return address
    ; X: unknown
    ; string: (after return address) null terminated filename, prepended with "S:"
    ; word: (after return address) address
    ; word: (after return address) size
    IO_save_file_entry:
        ; ### store or save x
        ; ### TODO ###
        pla                            ; load return address to copy opcode
        sta save_file_copyname_address_low
        pla
        sta save_file_copyname_address_high

    save_file_copyname:
        inc save_file_copyname_address_low     ; increase by one
        bne @skip
        inc save_file_copyname_address_high
    @skip:
    save_file_copyname_address_low = save_file_copyname_address + 1
    save_file_copyname_address_high = save_file_copyname_address + 2
    save_file_copyname_address:
        lda $ffff                      ; save ###
        bne save_file_copyname

        lda #$04
        clc
        adc save_file_copyname_address_low
        sta save_file_copyname_address_low
        bne @skip
        inc save_file_copyname_address_high
    @skip:
        lda save_file_copyname_address_high    ; return address on stack
        pha
        lda save_file_copyname_address_low
        pha
        rts


    ; --------------------------------------------------------------------
    ; IO_read_block_entry
    ; y:track x:sector a:high destination address
    IO_read_block_entry:
         ; save destination address
        pha

        ; correct track offset
        ; britannia (0x42), underworld (0x48): 19/0 - 35/15
        ; towne (0x43), dwelling (0x44), castle (0x45), keep (0x56): 24/0 - 35/15
        ; dungeon (0x47): 25/0 - 35/15
        tya        ; track in A, Y is free now
        clc
        sbc #$13   ; reduce by 0x19

        ; if 0x42 we are done
        ldy #$42
        cpy requested_disk
        beq track_corrected

        ; if 0x42 we are done
        ldy #$48
        cpy requested_disk
        beq track_corrected

        clc
        sbc #$05   ; reduce by 5

        ; if 0x47, reduce by one
        ldy #$47
        cpy requested_disk
        bne track_corrected
        clc
        sbc #$01
    track_corrected:

        ; calculate offset, track is in A
        asl      ; multiply track with 16 and add sector
        asl
        asl
        asl
        sta load_block_offset  ; store in temp
        txa      ; sector was in X
        clc
        adc load_block_offset
        tax      ; offset in X

        ; set filename
        ldy #$06
    @repeat:
        lda read_block_filename, y
        sta requested_filename, y
        dey
        bne @repeat

        ; address high byte
        lda #$ff
        sta load_strategy
        pla
        sta load_block_highdestination ; >0 will load a block
        jmp load_file_from_ef          ; load file: X: in file offset
    load_block_offset:
        .byte $00


    ; --------------------------------------------------------------------
    ; meaning of function unclear, copied from temp.subs
    ; parameter a, x
    ; some calculations to get the track and number from a
    IO_read_block_alt_entry:
        sta alt_sector
        sta alt_track
        txa
        lsr a
        ror alt_track
        lsr alt_track
        lsr alt_track
        lda alt_sector
        and #$07
        asl a
        sta alt_sector
        lda #$7e
        ldy alt_track
        ldx alt_sector
        jsr IO_read_block_entry
        lda #$7f
        ldy alt_track
        ldx alt_sector
        inx
        jmp IO_read_block_entry
    alt_track:  ; 6eac
        .byte $00
    alt_sector: ; 6ead
        .byte $00


    ; ====================================================================
    ; library wide variables

    requested_fullname:
    requested_disk:
        .byte $41
    requested_filename:
        .byte $00, $00, $00, $00, $00, $00, $00
        .byte $00, $00, $00, $00, $00, $00, $00, $00
    read_block_filename:
        .byte "BLOCK", $00
    bank_strategy:
        .byte $00
    load_strategy:    ; 00: decrunch; ff: load block; 01: load prg
        .byte $00


    ; ====================================================================
    ; load file

    ; --------------------------------------------------------------------
    load_file_from_ef:
        ; name in fixed location: requested_disk + requested_filename
        ; load_block_highdestination: set as destination address in non prg
        ; files
        ; X: in datafile offset: 0  for prg, 0-255 for blocks
        ; return c set on error
        ; search in files
        lda #EFS_FILES_BANKSTRATEGY
        sta bank_strategy
        lda #EFS_FILES_LOADSTRATEGY
        sta load_strategy
        lda #EFS_FILES_DIR_BANK
        ldy #>EFS_FILES_DIR_START
        jsr start_directory_search
        jsr find_directoryentry
        bcc filefound

        ; search in saves
        lda #EFS_SAVES_BANKSTRATEGY
        sta bank_strategy
        lda #EFS_SAVES_LOADSTRATEGY
        sta load_strategy
        lda #EFS_SAVES_DIR_BANK
        ldy #>EFS_SAVES_DIR_START
        jsr start_directory_search
        jsr find_directoryentry
        bcc filefound

        ; search in britannia ulist
        lda #EFS_BTLIST_BANKSTRATEGY
        sta bank_strategy
        lda #EFS_BTLIST_LOADSTRATEGY
        sta load_strategy
        lda #EFS_BTLIST_DIR_BANK
        ldy #>EFS_BTLIST_DIR_START
        jsr start_directory_search
        jsr find_directoryentry
        bcc filefound

        ; search in underworld ulist
        lda #EFS_UTLIST_BANKSTRATEGY
        sta bank_strategy
        lda #EFS_UTLIST_LOADSTRATEGY
        sta load_strategy
        lda #EFS_UTLIST_DIR_BANK
        ldy #>EFS_UTLIST_DIR_START
        jsr start_directory_search
        jsr find_directoryentry
        bcc filefound

        ; not found
        jsr finish_directory_search
        sec 
        rts

    filefound:
        txa                        ; X register is now free
        ldy #efs_directory::offset_high ; entry high offset
        clc
        adc ($fe), y               ; add offset to entry-offset
        tax                        ; uncorrected high offset in X
        ror                        ; move lower bits out, but save carry
        clc                        ; to prepare the correct bank in A
        ror                        ; 6 bit are the offset, therefore 6 shifts
        clc
        ror
        clc
        ror
        clc
        ror
        clc
        ror
        ldy #efs_directory::bank   ; entry bank
        clc
        adc ($fe), y
        pha                        ; bank is now on stack

        txa        ; high offset in A
        clc
        adc #$80   ; add $80 for correct memory range
        sta $fd    ; high offset in temp

        ldy #efs_directory::offset_low ; entry low offset 
        lda ($fe), y                   ; in A

        tax                        ; low offset in x
        ldy $fd                    ; high offset in y
        lda bank_strategy          ; bank strategy
        jsr EAPISetPtr
        pla                        ; bank
        jsr EAPISetBank            ; now we cannot access the directory anymore

        lda load_strategy          ; if zero, we decrunch prg
        bne otherloader
        lda $a7                    ; save zp variables (except $fc-$ff)
        pha
        lda $ae
        pha
        lda $af
        pha
        jsr EXO_decrunch
        pla
        sta $af
        pla
        sta $ae
        pla
        sta $a7
        clc        ; indicate success
        rts
    otherloader:
        bmi prgloader
        jmp load_block
    prgloader:
        jmp load_prg


    ; ====================================================================
    ; loading file utility, search in several ef
    ; uses fd, fe, ff in zeropage

    ; --------------------------------------------------------------------
    start_directory_search:
        ; A: bank, Y: address high
        ; directory must be increased  before first usage
        ; set bank
        jsr EAPISetBank

        ; bank in and set ($fe) to one element before
        lda #$07
        sta $01
        lda #EASYFLASH_LED | EASYFLASH_16K
        sta EASYFLASH_CONTROL
        dey
        sty $ff
        lda #$e8   ; 0x00 - 0x18
        sta $fe
        rts


    ; --------------------------------------------------------------------
    finish_directory_search:
        lda #EASYFLASH_KILL
        sta EASYFLASH_CONTROL
        lda #$06
        sta $01
        rts


    ; --------------------------------------------------------------------
    find_directoryentry:
        ; name set in fixed location: requested_fullname
        ; A: directory bank, X: start address of directory
        ; set pointer to matched directory entry
        ; C set on not found or other error
        ; C clear on found
        ; modified register: A, Y, status
        ;jsr start_directory_search
    nextname:
        ; increase for next pointer
        clc
        lda #$18   ; size of dir element
        adc $fe
        sta $fe
        bcc @nohighadd
        inc $ff
    @nohighadd:

        ; test if directory overflow
        lda #$18
        cmp $ff
        bcs notfound     ; if A >= $18
        ; more elements in directory possible
        ldy #efs_directory::flags  ; test if directory terminator
        lda #$1f
        and ($fe), y
        sta $fd
        lda #$1f
        cmp $fd
        bne morefiles
    notfound:
        ;jsr finish_directory_search  ; finish
        sec                          ; and set C
        rts
    morefiles:

        ; compare filename
        ldy #$ff
    nameloop:
        iny
        lda #$3f   ; '?'
        cmp requested_fullname, y  ; character in name is '?', go to next character
        beq nameloop
        lda #$2a   ; '*'
        cmp requested_fullname, y  ; character in name is '*', we have a match
        beq namematch
        lda requested_fullname, y  ; compare character with character in entry
        cmp ($fe), y               ; if not equal nextname
        bne nextname
        lda #$0                    ; compare if both character are zero
        cmp ($fe), y               ; if not, next name
        beq namematch
        jmp nameloop
        
    namematch:
        clc
        rts




