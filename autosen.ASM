
; CC5X Version 3.5G, Copyright (c) B Knudsen Data
; C compiler for the PICmicro family
; ************  15. Dec 2018  17:33  *************

        processor  12F508
        radix  DEC

        __config 0xE

TMR0        EQU   0x01
PORTB       EQU   0x06
Carry       EQU   0
Zero_       EQU   2
GPIO        EQU   0x06
GP0         EQU   0
GP1         EQU   1
GP2         EQU   2
GP3         EQU   3
Status      EQU   0x08
Zeit        EQU   0x09
OffZeit     EQU   0x0B
OnZeit      EQU   0x0D
LockZeit    EQU   0x0F
LED_referenz EQU   0
Taste1m     EQU   1
Taste2m     EQU   2
Tmerker     EQU   3
Tester1     EQU   4
Tester2     EQU   5
OldLED      EQU   6
Lock        EQU   7
ct0         EQU   0x12
ct1         EQU   0x13
i           EQU   0x14
key_state   EQU   0x15
key_press   EQU   0x16
chstate     EQU   0x07

        GOTO main

  ; FILE autosen.c
                        ;/*    AUTOSEN Autostart-Nachruestung fuer SENSEO-Maschinen          */
                        ;/*                       __    _                                    */                     
                        ;/*            __________/ /_  (_)________   ___  __  __             */       
                        ;/*           / ___/ ___/ __ \/ / ___/ __ \ / _ \/ / / /             */ 
                        ;/*          (__  ) /__/ / / / / /  / /_/ //  __/ /_/ /              */ 
                        ;/*         /____/\___/_/ /_/_/_/  / .___(_)___/\__,_/               */ 
                        ;/*                               /_/                                */ 
                        ;/*                                                                  */ 
                        ;/* (c) C.Schirp  released for non-commercial use                    */
                        ;/*     this header must be distributed with this source code        */ 
                        ;/*                                                                  */
                        ;/*     debounce routine by peter dannegger                          */
                        ;/*                                                                  */
                        ;/* V1.0  Erstausgabe                                                */
                        ;/* V1.1  activated internal PUs, earlier Portinit for stability     */
                        ;/* V1.2  Extrazeit nach Doppelklick fuer Off-Timer                  */
                        ;/* V1.2a Config-Bits jetzt enthalten                                */
                        ;/* V1.3  Sperrzeit gegen Fehlbedienung eingeführt                   */
                        ;/* V1.31 Laengere Tastendruck-Zeit für neue Senseos                 */
                        ;/*                                                                  */
                        ;
                        ;
                        ;#include "cc5x\12f508.h"
                        ;
                        ;
                        ;
                        ;#pragma config = 0x00E // 1110
                        ;// WD aktiv, kein ext. Reset, keine CP -> im Brenner gesetzt, INTRC=ON
                        ;// undokumentiert: Bit0 ist das "INTRC"-Bit, das gesetzt sein muss, sonst meldet der Programmer einen Fehler!
                        ;
                        ;// Defines fuer Status
                        ;#define BEGIN	 1
                        ;#define	TPRESS1  2
                        ;#define	TPRESS2	 3
                        ;#define LED_WAIT 4
                        ;#define	STABIL	 5
                        ;#define BTNPRESSED 6
                        ;#define RESTART  7
                        ;
                        ;#define AN 1
                        ;#define AUS 0
                        ;
                        ;// Defines fuer Wartezeiten
                        ;#define MSWAIT    4  /* Counterstand für 1ms */
                        ;#define BLINKZEIT 1172  /* ca. 1,2s */
                        ;#define KLICKZEIT 488   /* ca. 0,5s - 500ms */
                        ;#define TASTDRUCK 200    /* ca. 200ms */
                        ;#define MAXOFFTIME 1270 /* ca. 1,3 s */
                        ;#define MAXLOCKZEIT 4000 /* ca. 5 s */
                        ;
                        ;// Defines fuer Bit-Test Tastencodes
                        ;#define TASTE1	1
                        ;#define TASTE2  2
                        ;
                        ;
                        ;// Variablen
                        ;uns8 	Status;		// Zentrale Statusvariable
                        ;uns16	Zeit;		// Universalvariable zum Zeitmessen
                        ;uns16   OffZeit;	// Zeit bis Off-Zustand erkannt wird (wird runtergezählt)
                        ;uns16 	OnZeit;		// Zeit bis Aufgeheizt-Zustand erkannt wird (wird runtergezählt)
                        ;uns16	LockZeit;	// Zeit bis Lock freigegeben wird
                        ;uns8	LED_referenz:1;	// Referenzmerker für die LED-Flankenerkennung
                        ;uns8	Taste1m:1;	// Merker für Taste 1
                        ;uns8	Taste2m:1;	// Merker für Taste 1
                        ;uns8	Tmerker:1;	// Umschaltmerker T1/T2
                        ;uns8	Tester1:1;	// Hilfsvariable 1
                        ;uns8	Tester2:1;	// Hilfsvariable 1
                        ;uns8	OldLED:1;	// Merker fuer alten LED-Status zur Flankenerkennung
                        ;uns8	Lock:1;		// Autostart-Lock für MAXLOCKZEIT
                        ;
                        ;// Variablen für debouncing
                        ;uns8 ct0, ct1;
                        ;uns8 i;
                        ;uns8 key_state;
                        ;uns8 key_press;
                        ;
                        ;
                        ;// HW-Mapping
                        ;#define	Taste_akt1 GP0
                        ;#define	Taste_akt2 GP1
                        ;#define AKTIV_port GP2  /* LED am Aktiv-Port blinkt antiparallel zur Power-LED, wenn Autostart aktiv */
                        ;#define	LED_port GP3	/* GP3 kann nur als Eingang benutzt werden */
                        ;
                        ;void init(void)
                        ;{
init
                        ;	clrwdt();
        CLRWDT
                        ;	OPTION = 0b.1001.0111;	// weak PU enabled, TM0 in Timer-Mode, Prescaler zum Timer geschaltet
        MOVLW 151
        OPTION
                        ;	
                        ;	AKTIV_port = AUS;	// Autostart-LED sofort aus
        BCF   0x06,GP2
                        ;
                        ;	TRISGPIO = 0b.0000.1011; // 0,1,3 input, 2 Output
        MOVLW 11
        TRIS  PORTB
                        ;	
                        ;	// Entprellung zurücksetzen
                        ;	key_state = 0xFF;
        MOVLW 255
        MOVWF key_state
                        ;	ct0 = key_state;
        MOVF  key_state,W
        MOVWF ct0
                        ;	ct1 = ct0;
        MOVF  ct0,W
        MOVWF ct1
                        ;	
                        ;	// Variablen
                        ;	Status = RESTART;
        MOVLW 7
        MOVWF Status
                        ;	OldLED = 0;
        BCF   0x11,OldLED
                        ;	OnZeit = 0;
        CLRF  OnZeit
        CLRF  OnZeit+1
                        ;	LockZeit = 0;
        CLRF  LockZeit
        CLRF  LockZeit+1
                        ;	Lock = 0;
        BCF   0x11,Lock
                        ;	OffZeit = 0;
        CLRF  OffZeit
        CLRF  OffZeit+1
                        ;}
        RETLW 0
                        ;
                        ;// Debouncing von Peter Dannegger
                        ;void debounce(void)
                        ;{
debounce
                        ;  i = key_state ^ ~GPIO;	// key changed ?
        COMF  GPIO,W
        XORWF key_state,W
        MOVWF i
                        ;  ct0 = ~( ct0 & i );		// reset or count ct0
        MOVF  i,W
        ANDWF ct0,W
        XORLW 255
        MOVWF ct0
                        ;  ct1 = ct0 ^ (ct1 & i);	// reset or count ct1
        MOVF  i,W
        ANDWF ct1,W
        XORWF ct0,W
        MOVWF ct1
                        ;  i &= ct0 & ct1;		// count until roll over
        MOVF  ct1,W
        ANDWF ct0,W
        ANDWF i,1
                        ;  key_state ^= i;		// then toggle debounced state
        MOVF  i,W
        XORWF key_state,1
                        ;  key_press |= key_state & i;	// 0->1: key pressing detect
        MOVF  i,W
        ANDWF key_state,W
        IORWF key_press,1
                        ;}
        RETLW 0
                        ;
                        ;// Auf Taste testen, wenn druecken erkannt Status auf chstate aendern
                        ;void Taste_testen(uns8 chstate)
                        ;{
Taste_testen
        MOVWF chstate
                        ;	if (key_press & TASTE1)
        BTFSS key_press,0
        GOTO  m001
                        ;	{
                        ;		Taste1m = 1;		// merken: Taste 1 war es
        BSF   0x11,Taste1m
                        ;		Status = chstate;	// Sollstatus uebernehmen
        MOVF  chstate,W
        MOVWF Status
                        ;		key_press ^= TASTE1;	// und den Tastendruck loeschen
        MOVLW 1
        XORWF key_press,1
                        ;	}
                        ;	else
        GOTO  m002
                        ;	{
                        ;		Taste1m = 0;
m001    BCF   0x11,Taste1m
                        ;	}
                        ;	
                        ;	if (key_press & TASTE2)
m002    BTFSS key_press,1
        GOTO  m003
                        ;	{
                        ;		Taste2m = 1;		// merken: Taste 2 war es
        BSF   0x11,Taste2m
                        ;		Status = chstate;	// Sollstatus uebernehmen
        MOVF  chstate,W
        MOVWF Status
                        ;		key_press ^= TASTE2;	// und den Tastendruck loeschen
        MOVLW 2
        XORWF key_press,1
                        ;	}
                        ;	else
        GOTO  m004
                        ;	{
                        ;		Taste2m = 0;
m003    BCF   0x11,Taste2m
                        ;	}	
                        ;}
m004    RETLW 0
                        ;
                        ;
                        ;// Zeitmessung resetten
                        ;void Uhr_starten(void)
                        ;{
Uhr_starten
                        ;	TMR0=0;
        CLRF  TMR0
                        ;	Zeit=0;
        CLRF  Zeit
        CLRF  Zeit+1
                        ;}
        RETLW 0
                        ;
                        ;// rund 0,001024s warten (1MHz clock / 256 Vorteiler / Zählerstand 4)
                        ;void wait1ms(void)
                        ;{
wait1ms
                        ;	TMR0 = 0;
        CLRF  TMR0
                        ;	while (TMR0 < MSWAIT);
m005    MOVLW 4
        SUBWF TMR0,W
        BTFSC 0x03,Carry
        GOTO  m006
        GOTO  m005
                        ;		
                        ;}
m006    RETLW 0
                        ;
                        ;
                        ;// Test auf "Off-Zustand"
                        ;void OffTest(void)
                        ;{
OffTest
                        ;
                        ;	if (LED_port)
        BTFSS 0x06,GP3
        GOTO  m007
                        ;	{
                        ;		// LED an, dann Uhr aufziehen
                        ;		OffZeit	= MAXOFFTIME;
        MOVLW 246
        MOVWF OffZeit
        MOVLW 4
        MOVWF OffZeit+1
                        ;			
                        ;	}
                        ;	else if (OffZeit > 0)
        GOTO  m009
m007    MOVF  OffZeit,W
        IORWF OffZeit+1,W
        BTFSC 0x03,Zero_
        GOTO  m008
                        ;	{
                        ;		// LED ist zwar aus, aber Zeit noch nicht abgelaufen
                        ;		OffZeit--;
        DECF  OffZeit,1
        INCF  OffZeit,W
        BTFSC 0x03,Zero_
        DECF  OffZeit+1,1
                        ;	}
                        ;	else
        GOTO  m009
                        ;	{
                        ;		Status = RESTART; // Off-Zustand erkannt: immer im RESET-Status hängenbleiben
m008    MOVLW 7
        MOVWF Status
                        ;	}
                        ;	
                        ;}
m009    RETLW 0
                        ;
                        ;// Test auf Lock-Zustand
                        ;// Wenn die LED länger als MAXOFFTIME eingeschaltet ist, wird Lock gesetzt und LockZeit auf Maxlockzeit aufgezogen
                        ;// erst wenn die LED mal wieder aus ist, wird der OnZeit-Timer mal wieder gestartet & Lockzeit nicht mehr auf Max gesetzt,
                        ;// so dass der Lockzeit-Timer abläuft und das Lock wieder freigegeben wird.
                        ;void LockTest(void)
                        ;{
LockTest
                        ;
                        ;	if (LED_port)
        BTFSS 0x06,GP3
        GOTO  m013
                        ;	{
                        ;		// wenn vorher aus war, Zeitmessung starten
                        ;		if (!OldLED)
        BTFSC 0x11,OldLED
        GOTO  m010
                        ;		{
                        ;			OnZeit = MAXOFFTIME;
        MOVLW 246
        MOVWF OnZeit
        MOVLW 4
        MOVWF OnZeit+1
                        ;		}
                        ;		else if (OnZeit > 0)
        GOTO  m012
m010    MOVF  OnZeit,W
        IORWF OnZeit+1,W
        BTFSC 0x03,Zero_
        GOTO  m011
                        ;		{
                        ;			// 
                        ;			OnZeit--;
        DECF  OnZeit,1
        INCF  OnZeit,W
        BTFSC 0x03,Zero_
        DECF  OnZeit+1,1
                        ;		}
                        ;		else // LED ist laenger als 1,3 s an -> Autostart sperren
        GOTO  m012
                        ;		{
                        ;			Lock = 1;
m011    BSF   0x11,Lock
                        ;			LockZeit = MAXLOCKZEIT;
        MOVLW 160
        MOVWF LockZeit
        MOVLW 15
        MOVWF LockZeit+1
                        ;		}
                        ;			
                        ;	}
                        ;	else // LED ist  aus
m012    GOTO  m013
                        ;	{
                        ;		// egal
                        ;	}
                        ;	
                        ;	if (LockZeit > 0)
m013    MOVF  LockZeit,W
        IORWF LockZeit+1,W
        BTFSC 0x03,Zero_
        GOTO  m014
                        ;	{
                        ;		// 
                        ;		LockZeit--;
        DECF  LockZeit,1
        INCF  LockZeit,W
        BTFSC 0x03,Zero_
        DECF  LockZeit+1,1
                        ;	}
                        ;	else // Lockzeit ist abgelaufen, Lock freigeben
        GOTO  m015
                        ;	{
                        ;		Lock = 0;
m014    BCF   0x11,Lock
                        ;	}
                        ;	
                        ;	// alten Zustand merken
                        ;	OldLED = LED_port;
m015    BCF   0x11,OldLED
        BTFSC 0x06,GP3
        BSF   0x11,OldLED
                        ;	
                        ;}
        RETLW 0
                        ;
                        ;
                        ;// Tastenemulation betaetigen betätigt
                        ;void Taste_an(void)
                        ;{
Taste_an
                        ;	// Je nach Taste 1/2 Puls setzen	
                        ;	if (Tmerker)
        BTFSS 0x11,Tmerker
        GOTO  m016
                        ;	{
                        ;		Taste_akt2 = 0;		// LOW anlegen
        BCF   0x06,GP1
                        ;		TRISGPIO = 0b.0000.1001;	// Tastenpin 2 als Output schalten			
        MOVLW 9
        TRIS  PORTB
                        ;	}
                        ;	else
        GOTO  m017
                        ;	{
                        ;		Taste_akt1 = 0;		// LOW anlegen
m016    BCF   0x06,GP0
                        ;		TRISGPIO = 0b.0000.1010;	// Tastenpin 1 als Output schalten
        MOVLW 10
        TRIS  PORTB
                        ;	}
                        ;}
m017    RETLW 0
                        ;
                        ;// Tastenemulation wieder auf nicht betätigt
                        ;void Taste_aus(void)
                        ;{
Taste_aus
                        ;	TRISGPIO = 0b.0000.1011;	// Tastenpins als Input schalten
        MOVLW 11
        TRIS  PORTB
                        ;					
                        ;	// Je nach Taste 1/2 Puls wieder loeschen
                        ;	if (Tmerker)
        BTFSS 0x11,Tmerker
        GOTO  m018
                        ;	{
                        ;		Taste_akt2 = 1;		// High anlegen	
        BSF   0x06,GP1
                        ;	}
                        ;	else
        GOTO  m019
                        ;	{
                        ;		Taste_akt1 = 1;		// High anlegen
m018    BSF   0x06,GP0
                        ;	}
                        ;}
m019    RETLW 0
                        ;
                        ;
                        ;void main (void)
                        ;{
main
                        ;	
                        ;	init();
        CALL  init
                        ;	
                        ;	while (1)
                        ;	{
                        ;		clrwdt();
m020    CLRWDT
                        ;		// i/O einlesen
                        ;		debounce();
        CALL  debounce
                        ;		// 1ms-Takt
                        ;		wait1ms();
        CALL  wait1ms
                        ;		// Uhr weiterzählen
                        ;		Zeit++;	
        INCF  Zeit,1
        BTFSC 0x03,Zero_
        INCF  Zeit+1,1
                        ;		// Aus-Zustand immer abprüfen
                        ;		OffTest();
        CALL  OffTest
                        ;		// Lockzustand prüfen
                        ;		LockTest();
        CALL  LockTest
                        ;		
                        ;		if (Status == BEGIN)
        DECF  Status,W
        BTFSS 0x03,Zero_
        GOTO  m024
                        ;		{
                        ;			// Tastendruck testen, wenn nicht gelockt
                        ;			if (!Lock)
        BTFSC 0x11,Lock
        GOTO  m021
                        ;			{
                        ;				Taste_testen(TPRESS1);
        MOVLW 2
        CALL  Taste_testen
                        ;			}
                        ;			
                        ;			// wenn Tastendruck T1 erkannt, Uhr starten, Taste merken
                        ;			if (Taste1m)
m021    BTFSS 0x11,Taste1m
        GOTO  m022
                        ;			{
                        ;				Uhr_starten();
        CALL  Uhr_starten
                        ;				Tmerker = 0;
        BCF   0x11,Tmerker
                        ;			}
                        ;			
                        ;			// wenn Tastendruck T2 erkannt, Uhr starten, Taste merken
                        ;			else if (Taste2m)
        GOTO  m023
m022    BTFSS 0x11,Taste2m
        GOTO  m023
                        ;			{
                        ;				Uhr_starten();
        CALL  Uhr_starten
                        ;				Tmerker = 1;
        BSF   0x11,Tmerker
                        ;			}
                        ;		}
                        ;		// Zustand nach Taste 1x gedrückt
                        ;		else if (Status == TPRESS1)
m023    GOTO  m028
m024    MOVF  Status,W
        XORLW 2
        BTFSS 0x03,Zero_
        GOTO  m028
                        ;		{
                        ;			// Tastendruck testen 
                        ;			Taste_testen(TPRESS1);
        MOVLW 2
        CALL  Taste_testen
                        ;			
                        ;			// Bitvariablen ausrechnen (Compilerbeschraenkung, geht nicht im if() )
                        ;			Tester1 = !Tmerker;
        BSF   0x11,Tester1
        BTFSC 0x11,Tmerker
        BCF   0x11,Tester1
                        ;			Tester1 &= Taste1m;
        BTFSS 0x11,Taste1m
        BCF   0x11,Tester1
                        ;			Tester2 = Taste2m;
        BCF   0x11,Tester2
        BTFSC 0x11,Taste2m
        BSF   0x11,Tester2
                        ;			Tester2 &= Tmerker;
        BTFSS 0x11,Tmerker
        BCF   0x11,Tester2
                        ;			
                        ;			// wenn gleicher Tastendruck erkannt, nächster State
                        ;			if (Tester1)
        BTFSS 0x11,Tester1
        GOTO  m025
                        ;			{
                        ;				Status = TPRESS2;
        MOVLW 3
        MOVWF Status
                        ;			}
                        ;			else if (Tester2)
        GOTO  m028
m025    BTFSS 0x11,Tester2
        GOTO  m026
                        ;			{
                        ;				Status = TPRESS2;
        MOVLW 3
        MOVWF Status
                        ;			}
                        ;			
                        ;			// wenn die Doppelklickzeit abgelaufen ist, wieder alles auf Anfang
                        ;			else if (Zeit > KLICKZEIT)
        GOTO  m028
m026    MOVLW 1
        SUBWF Zeit+1,W
        BTFSS 0x03,Carry
        GOTO  m028
        BTFSS 0x03,Zero_
        GOTO  m027
        MOVLW 233
        SUBWF Zeit,W
        BTFSS 0x03,Carry
        GOTO  m028
                        ;			{
                        ;				Status = RESTART;
m027    MOVLW 7
        MOVWF Status
                        ;			}
                        ;
                        ;		}
                        ;		// Zustand nach Taste 2x gedrückt,  LED-Signal samplen
                        ;		if (Status == TPRESS2)
m028    MOVF  Status,W
        XORLW 3
        BTFSS 0x03,Zero_
        GOTO  m029
                        ;		{		
                        ;			LED_referenz=LED_port;
        BCF   0x11,LED_referenz
        BTFSC 0x06,GP3
        BSF   0x11,LED_referenz
                        ;			Uhr_starten();
        CALL  Uhr_starten
                        ;			Status = LED_WAIT;
        MOVLW 4
        MOVWF Status
                        ;			// nach Doppelclick nochmal Extrazeit wegen Bug in der HD7810/69/A
                        ;			OffZeit	= MAXOFFTIME;
        MOVLW 246
        MOVWF OffZeit
        MOVLW 4
        MOVWF OffZeit+1
                        ;		}
                        ;
                        ;		//warten auf stabiles LED-Signal		
                        ;		if (Status == LED_WAIT)
m029    MOVF  Status,W
        XORLW 4
        BTFSS 0x03,Zero_
        GOTO  m036
                        ;		{
                        ;			// erneuter Tastendruck bricht ab
                        ;			Taste_testen(RESTART);
        MOVLW 7
        CALL  Taste_testen
                        ;			
                        ;			// Aktiv-LED blinken lassen
                        ;			if (LED_port)
        BTFSS 0x06,GP3
        GOTO  m030
                        ;			{
                        ;				AKTIV_port = AUS;
        BCF   0x06,GP2
                        ;			}
                        ;			else
        GOTO  m031
                        ;			{
                        ;				AKTIV_port = AN;
m030    BSF   0x06,GP2
                        ;			}
                        ;			
                        ;			// wenn sich der LED-Zustand geändert hat, neu starten
                        ;			if (LED_referenz != LED_port)
m031    BTFSC 0x11,LED_referenz
        GOTO  m032
        BTFSC 0x06,GP3
        GOTO  m033
        GOTO  m034
m032    BTFSC 0x06,GP3
        GOTO  m034
                        ;			{
                        ;				LED_referenz=LED_port;
m033    BCF   0x11,LED_referenz
        BTFSC 0x06,GP3
        BSF   0x11,LED_referenz
                        ;				Uhr_starten();
        CALL  Uhr_starten
                        ;			}	
                        ;			
                        ;			// Zeit abgelaufen, länger als 1,2s stabil, unsere LED aus
                        ;			if (Zeit > BLINKZEIT)
m034    MOVLW 4
        SUBWF Zeit+1,W
        BTFSS 0x03,Carry
        GOTO  m036
        BTFSS 0x03,Zero_
        GOTO  m035
        MOVLW 149
        SUBWF Zeit,W
        BTFSS 0x03,Carry
        GOTO  m036
                        ;			{
                        ;				Status = STABIL;
m035    MOVLW 5
        MOVWF Status
                        ;				AKTIV_port = AUS;
        BCF   0x06,GP2
                        ;			}
                        ;			
                        ;		}
                        ;		// wir haben einen stabilen LED-Zustand!
                        ;		if (Status == STABIL)
m036    MOVF  Status,W
        XORLW 5
        BTFSS 0x03,Zero_
        GOTO  m038
                        ;		{
                        ;			// Wenn LED an ist, Knopf drücken!
                        ;			if (LED_port == AN)
        BTFSS 0x06,GP3
        GOTO  m037
                        ;			{
                        ;				Taste_an();
        CALL  Taste_an
                        ;				
                        ;				Uhr_starten();
        CALL  Uhr_starten
                        ;				
                        ;				Status = BTNPRESSED;
        MOVLW 6
        MOVWF Status
                        ;			}
                        ;			else
        GOTO  m038
                        ;			{
                        ;				Status = RESTART;
m037    MOVLW 7
        MOVWF Status
                        ;			}
                        ;		}
                        ;		
                        ;		if (Status == BTNPRESSED)
m038    MOVF  Status,W
        XORLW 6
        BTFSS 0x03,Zero_
        GOTO  m040
                        ;		{
                        ;			// wenn Taste lang genug gedrückt -> alles auf Anfang
                        ;			if (Zeit > TASTDRUCK)
        MOVF  Zeit+1,W
        BTFSS 0x03,Zero_
        GOTO  m039
        MOVLW 201
        SUBWF Zeit,W
        BTFSS 0x03,Carry
        GOTO  m040
                        ;			{
                        ;				Taste_aus();
m039    CALL  Taste_aus
                        ;				
                        ;				Status = RESTART;	
        MOVLW 7
        MOVWF Status
                        ;			}
                        ;		}
                        ;		
                        ;		// alles auf Anfang setzen
                        ;		if (Status == RESTART)
m040    MOVF  Status,W
        XORLW 7
        BTFSS 0x03,Zero_
        GOTO  m041
                        ;		{
                        ;			Taste1m = 0; /* beide Tastenmerker zuruecksetzen */
        BCF   0x11,Taste1m
                        ;			Taste2m = 0;
        BCF   0x11,Taste2m
                        ;			Status = BEGIN;
        MOVLW 1
        MOVWF Status
                        ;			AKTIV_port = AUS;
        BCF   0x06,GP2
                        ;		}
                        ;	}; // von while(1)
m041    GOTO  m020

        END


; *** KEY INFO ***

; 0x0001   23 word(s)  4 % : init
; 0x0018   20 word(s)  3 % : debounce
; 0x002C   20 word(s)  3 % : Taste_testen
; 0x0040    4 word(s)  0 % : Uhr_starten
; 0x0044    7 word(s)  1 % : wait1ms
; 0x004B   19 word(s)  3 % : OffTest
; 0x005E   38 word(s)  7 % : LockTest
; 0x0084   10 word(s)  1 % : Taste_an
; 0x008E    8 word(s)  1 % : Taste_aus
; 0x0096  150 word(s) 29 % : main

; RAM usage: 16 bytes (1 local), 9 bytes free
; Maximum call level: 1
; Total of 300 code words (58 %)
