/*    AUTOSEN Autostart-Nachruestung fuer SENSEO-Maschinen          */
/*                       __    _                                    */                     
/*            __________/ /_  (_)________   ___  __  __             */       
/*           / ___/ ___/ __ \/ / ___/ __ \ / _ \/ / / /             */ 
/*          (__  ) /__/ / / / / /  / /_/ //  __/ /_/ /              */ 
/*         /____/\___/_/ /_/_/_/  / .___(_)___/\__,_/               */ 
/*                               /_/                                */ 
/*                                                                  */ 
/* (c) C.Schirp  released for non-commercial use                    */
/*     this header must be distributed with this source code        */ 
/*                                                                  */
/*     debounce routine by peter dannegger                          */
/*                                                                  */
/* V1.0  Erstausgabe                                                */
/* V1.1  activated internal PUs, earlier Portinit for stability     */
/* V1.2  Extrazeit nach Doppelklick fuer Off-Timer                  */
/* V1.2a Config-Bits jetzt enthalten                                */
/* V1.3  Sperrzeit gegen Fehlbedienung eingeführt                   */
/* V1.31 Laengere Tastendruck-Zeit für neue Senseos                 */
/*                                                                  */


#include "cc5x\12F509.h"



#pragma config = 0x00E // 1110
// WD aktiv, kein ext. Reset, keine CP -> im Brenner gesetzt, INTRC=ON
// undokumentiert: Bit0 ist das "INTRC"-Bit, das gesetzt sein muss, sonst meldet der Programmer einen Fehler!

// Defines fuer Status
#define BEGIN	 1
#define	TPRESS1  2
#define	TPRESS2	 3
#define LED_WAIT 4
#define	STABIL	 5
#define BTNPRESSED 6
#define RESTART  7

#define AN 1
#define AUS 0

// Defines fuer Wartezeiten
#define MSWAIT    4  /* Counterstand für 1ms */
#define BLINKZEIT 1172  /* ca. 1,2s */
#define KLICKZEIT 488   /* ca. 0,5s - 500ms */
#define TASTDRUCK 200    /* ca. 200ms */
#define MAXOFFTIME 1270 /* ca. 1,3 s */
#define MAXLOCKZEIT 4000 /* ca. 5 s */

// Defines fuer Bit-Test Tastencodes
#define TASTE1	1
#define TASTE2  2


// Variablen
uns8 	Status;		// Zentrale Statusvariable
uns16	Zeit;		// Universalvariable zum Zeitmessen
uns16   OffZeit;	// Zeit bis Off-Zustand erkannt wird (wird runtergezählt)
uns16 	OnZeit;		// Zeit bis Aufgeheizt-Zustand erkannt wird (wird runtergezählt)
uns16	LockZeit;	// Zeit bis Lock freigegeben wird
uns8	LED_referenz:1;	// Referenzmerker für die LED-Flankenerkennung
uns8	Taste1m:1;	// Merker für Taste 1
uns8	Taste2m:1;	// Merker für Taste 1
uns8	Tmerker:1;	// Umschaltmerker T1/T2
uns8	Tester1:1;	// Hilfsvariable 1
uns8	Tester2:1;	// Hilfsvariable 1
uns8	OldLED:1;	// Merker fuer alten LED-Status zur Flankenerkennung
uns8	Lock:1;		// Autostart-Lock für MAXLOCKZEIT

// Variablen für debouncing
uns8 ct0, ct1;
uns8 i;
uns8 key_state;
uns8 key_press;


// HW-Mapping
#define	Taste_akt1 GP0
#define	Taste_akt2 GP1
#define AKTIV_port GP2  /* LED am Aktiv-Port blinkt antiparallel zur Power-LED, wenn Autostart aktiv */
#define	LED_port GP3	/* GP3 kann nur als Eingang benutzt werden */

void init(void)
{
	clrwdt();
	OPTION = 0b.1001.0111;	// weak PU enabled, TM0 in Timer-Mode, Prescaler zum Timer geschaltet
	
	AKTIV_port = AUS;	// Autostart-LED sofort aus

	TRISGPIO = 0b.0000.1011; // 0,1,3 input, 2 Output
	
	// Entprellung zurücksetzen
	key_state = 0xFF;
	ct0 = key_state;
	ct1 = ct0;
	
	// Variablen
	Status = RESTART;
	OldLED = 0;
	OnZeit = 0;
	LockZeit = 0;
	Lock = 0;
	OffZeit = 0;
}

// Debouncing von Peter Dannegger
void debounce(void)
{
  i = key_state ^ ~GPIO;	// key changed ?
  ct0 = ~( ct0 & i );		// reset or count ct0
  ct1 = ct0 ^ (ct1 & i);	// reset or count ct1
  i &= ct0 & ct1;		// count until roll over
  key_state ^= i;		// then toggle debounced state
  key_press |= key_state & i;	// 0->1: key pressing detect
}

// Auf Taste testen, wenn druecken erkannt Status auf chstate aendern
void Taste_testen(uns8 chstate)
{
	if (key_press & TASTE1)
	{
		Taste1m = 1;		// merken: Taste 1 war es
		Status = chstate;	// Sollstatus uebernehmen
		key_press ^= TASTE1;	// und den Tastendruck loeschen
	}
	else
	{
		Taste1m = 0;
	}
	
	if (key_press & TASTE2)
	{
		Taste2m = 1;		// merken: Taste 2 war es
		Status = chstate;	// Sollstatus uebernehmen
		key_press ^= TASTE2;	// und den Tastendruck loeschen
	}
	else
	{
		Taste2m = 0;
	}	
}


// Zeitmessung resetten
void Uhr_starten(void)
{
	TMR0=0;
	Zeit=0;
}

// rund 0,001024s warten (1MHz clock / 256 Vorteiler / Zählerstand 4)
void wait1ms(void)
{
	TMR0 = 0;
	while (TMR0 < MSWAIT);
		
}


// Test auf "Off-Zustand"
void OffTest(void)
{

	if (LED_port)
	{
		// LED an, dann Uhr aufziehen
		OffZeit	= MAXOFFTIME;
			
	}
	else if (OffZeit > 0)
	{
		// LED ist zwar aus, aber Zeit noch nicht abgelaufen
		OffZeit--;
	}
	else
	{
		Status = RESTART; // Off-Zustand erkannt: immer im RESET-Status hängenbleiben
	}
	
}

// Test auf Lock-Zustand
// Wenn die LED länger als MAXOFFTIME eingeschaltet ist, wird Lock gesetzt und LockZeit auf Maxlockzeit aufgezogen
// erst wenn die LED mal wieder aus ist, wird der OnZeit-Timer mal wieder gestartet & Lockzeit nicht mehr auf Max gesetzt,
// so dass der Lockzeit-Timer abläuft und das Lock wieder freigegeben wird.
void LockTest(void)
{

	if (LED_port)
	{
		// wenn vorher aus war, Zeitmessung starten
		if (!OldLED)
		{
			OnZeit = MAXOFFTIME;
		}
		else if (OnZeit > 0)
		{
			// 
			OnZeit--;
		}
		else // LED ist laenger als 1,3 s an -> Autostart sperren
		{
			Lock = 1;
			LockZeit = MAXLOCKZEIT;
		}
			
	}
	else // LED ist  aus
	{
		// egal
	}
	
	if (LockZeit > 0)
	{
		// 
		LockZeit--;
	}
	else // Lockzeit ist abgelaufen, Lock freigeben
	{
		Lock = 0;
	}
	
	// alten Zustand merken
	OldLED = LED_port;
	
}


// Tastenemulation betaetigen betätigt
void Taste_an(void)
{
	// Je nach Taste 1/2 Puls setzen	
	if (Tmerker)
	{
		Taste_akt2 = 0;		// LOW anlegen
		TRISGPIO = 0b.0000.1001;	// Tastenpin 2 als Output schalten			
	}
	else
	{
		Taste_akt1 = 0;		// LOW anlegen
		TRISGPIO = 0b.0000.1010;	// Tastenpin 1 als Output schalten
	}
}

// Tastenemulation wieder auf nicht betätigt
void Taste_aus(void)
{
	TRISGPIO = 0b.0000.1011;	// Tastenpins als Input schalten
					
	// Je nach Taste 1/2 Puls wieder loeschen
	if (Tmerker)
	{
		Taste_akt2 = 1;		// High anlegen	
	}
	else
	{
		Taste_akt1 = 1;		// High anlegen
	}
}


void main (void)
{
	
	init();
	
	while (1)
	{
		clrwdt();
		// i/O einlesen
		debounce();
		// 1ms-Takt
		wait1ms();
		// Uhr weiterzählen
		Zeit++;	
		// Aus-Zustand immer abprüfen
		OffTest();
		// Lockzustand prüfen
		LockTest();
		
		if (Status == BEGIN)
		{
			// Tastendruck testen, wenn nicht gelockt
			if (!Lock)
			{
				Taste_testen(TPRESS1);
			}
			
			// wenn Tastendruck T1 erkannt, Uhr starten, Taste merken
			if (Taste1m)
			{
				Uhr_starten();
				Tmerker = 0;
			}
			
			// wenn Tastendruck T2 erkannt, Uhr starten, Taste merken
			else if (Taste2m)
			{
				Uhr_starten();
				Tmerker = 1;
			}
		}
		// Zustand nach Taste 1x gedrückt
		else if (Status == TPRESS1)
		{
			// Tastendruck testen 
			Taste_testen(TPRESS1);
			
			// Bitvariablen ausrechnen (Compilerbeschraenkung, geht nicht im if() )
			Tester1 = !Tmerker;
			Tester1 &= Taste1m;
			Tester2 = Taste2m;
			Tester2 &= Tmerker;
			
			// wenn gleicher Tastendruck erkannt, nächster State
			if (Tester1)
			{
				Status = TPRESS2;
			}
			else if (Tester2)
			{
				Status = TPRESS2;
			}
			
			// wenn die Doppelklickzeit abgelaufen ist, wieder alles auf Anfang
			else if (Zeit > KLICKZEIT)
			{
				Status = RESTART;
			}

		}
		// Zustand nach Taste 2x gedrückt,  LED-Signal samplen
		if (Status == TPRESS2)
		{		
			LED_referenz=LED_port;
			Uhr_starten();
			Status = LED_WAIT;
			// nach Doppelclick nochmal Extrazeit wegen Bug in der HD7810/69/A
			OffZeit	= MAXOFFTIME;
		}

		//warten auf stabiles LED-Signal		
		if (Status == LED_WAIT)
		{
			// erneuter Tastendruck bricht ab
			Taste_testen(RESTART);
			
			// Aktiv-LED blinken lassen
			if (LED_port)
			{
				AKTIV_port = AUS;
			}
			else
			{
				AKTIV_port = AN;
			}
			
			// wenn sich der LED-Zustand geändert hat, neu starten
			if (LED_referenz != LED_port)
			{
				LED_referenz=LED_port;
				Uhr_starten();
			}	
			
			// Zeit abgelaufen, länger als 1,2s stabil, unsere LED aus
			if (Zeit > BLINKZEIT)
			{
				Status = STABIL;
				AKTIV_port = AUS;
			}
			
		}
		// wir haben einen stabilen LED-Zustand!
		if (Status == STABIL)
		{
			// Wenn LED an ist, Knopf drücken!
			if (LED_port == AN)
			{
				Taste_an();
				
				Uhr_starten();
				
				Status = BTNPRESSED;
			}
			else
			{
				Status = RESTART;
			}
		}
		
		if (Status == BTNPRESSED)
		{
			// wenn Taste lang genug gedrückt -> alles auf Anfang
			if (Zeit > TASTDRUCK)
			{
				Taste_aus();
				
				Status = RESTART;	
			}
		}
		
		// alles auf Anfang setzen
		if (Status == RESTART)
		{
			Taste1m = 0; /* beide Tastenmerker zuruecksetzen */
			Taste2m = 0;
			Status = BEGIN;
			AKTIV_port = AUS;
		}
	}; // von while(1)

} // von main()	