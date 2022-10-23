
;--- to translate LFN chars 0080-00FF to ANSI (CP 1252?);
;--- currently just German umlauts.

oemchars label byte
;------- 0---1---2---3---4---5---6---7---8---9---A---B---C---D---E---F
    db   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0  ;80-8f
    db   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0  ;90-9f
    db   0,  0,  0,  0,  0,  0,  0, 21,  0,  0,  0,  0,  0,  0,  0,  0  ;a0-af
    db   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0  ;b0-bf
    db   0,  0,  0,  0,142,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0  ;c0-cf
    db   0,  0,  0,  0,  0,  0,153,  0,  0,  0,  0,  0,154,  0,  0,225  ;d0-df
    db   0,  0,  0,  0,132,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0  ;e0-ef
    db   0,  0,  0,  0,  0,  0,148,  0,  0,  0,  0,  0,129,  0,  0,  0  ;f0-ff

;--- valid OEM chars in SFNs.
;--- this table is used by WDe when it tries to detect a "directory" sector,
;--- and,if ok, will activate the "directory view".
;--- currently contains German upper case umlauts (8E/99/9A) and "sz" (E1) only.
;--- actually, many chars > 128 are accepted as valid SFN chars.

oembittab label word
;---------0---0---0---0
;---------C---8---4---0
	dw 0100000000000000b ;8X
	dw 0000011000000000b ;9X
	dw 0000000000000000b ;AX
	dw 0000000000000000b ;BX
	dw 0000000000000000b ;CX
	dw 0000000000000000b ;DX
	dw 0000000000000010b ;EX
	dw 0000000000000000b ;FX
