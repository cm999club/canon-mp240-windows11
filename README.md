# Canon PIXMA MP240 su Windows 10 / 11 (64 bit)

🇮🇹 Italiano · [🇬🇧 English below](#english)

Canon non ha mai rilasciato driver per la **PIXMA MP240** su Windows 10 e 11. Il driver ufficiale **MP Driver Ver. 1.02** per Windows 8.1 x64 però funziona benissimo. Il problema è solo l'installer Canon, che si blocca, e un errore di comunicazione USB (**errore 170 "La risorsa richiesta è in uso"**) per cui le stampe restano ferme in coda.

Questo script risolve tutto con un doppio clic, **usando solo il driver originale Canon, senza modificarlo**.

## Cosa fa

- Scarica il pacchetto **ufficiale** dal server Canon. Se il file ce l'hai già, usa quello.
- Controlla la **firma digitale Canon Inc.** e l'impronta **SHA-256** prima di installare.
- Installa il driver della stampante e quello dello scanner con `pnputil` (lo strumento di Windows), saltando l'installer Canon.
- Disattiva la **comunicazione bidirezionale**, cioè la causa dell'errore 170, e riavvia lo spooler di stampa.
- Stampa una pagina di prova.
- Ha un menu con: **Ripara** (coda bloccata, errore 170), **Diagnostica**, **Disinstalla** e **Pagina ufficiale Canon**.
- Mostra i messaggi in italiano o in inglese a seconda della lingua di Windows.
- Salva un log in `%TEMP%\CanonMP240_Win11.log`.

## Come si usa

1. Accendi la MP240 e collegala via USB, meglio su una porta diretta e non su un hub.
2. Scarica [`installa_canon_mp240_win11.cmd`](installa_canon_mp240_win11.cmd).
3. Fai **doppio clic** e conferma la richiesta di Windows, che chiede i permessi di amministratore.
4. Scegli **1 – Installa**. Se non hai il pacchetto Canon, lo script ti propone di scaricarlo dal server ufficiale.

> Se Windows SmartScreen mostra "Windows ha protetto il PC", clicca **Ulteriori informazioni → Esegui comunque**. Lo script è un file di testo: puoi aprirlo con il Blocco note e leggerlo prima di eseguirlo.

## Driver ufficiale Canon

| | |
|---|---|
| Pagina Canon | https://asia.canon/en/support/0100135901 |
| File | `md64-win-mp240-1_02-ea24.exe` (26.125.712 byte) |
| Download diretto | https://gdlp01.c-wss.com/gds/9/0100001359/03/md64-win-mp240-1_02-ea24.exe |
| SHA-256 | `39D327C8C8DB66BE3888000F20EAA50902CB3A2663B54F999F065124E8773E57` |

Il driver **non è incluso** in questo repository perché è software di Canon Inc. Lo script lo scarica direttamente da Canon.

## Problemi comuni

| Sintomo | Soluzione |
|---|---|
| La stampa resta in coda con "Errore" | Menu **2 – Ripara** |
| La stampante non compare dopo l'installazione | Scollega e ricollega l'USB, poi **2 – Ripara** |
| Il foglio esce bianco o a righe | Pulizia testine dal pannello della stampante o dalle Proprietà stampante → Manutenzione |
| Lo scanner non funziona | Usa l'app **Scanner di Windows** o **Fax e scanner di Windows** |

Testato su **Windows 11 Home 25H2 (build 26200)**.

---

<a id="english"></a>
## English

Canon never released **PIXMA MP240** drivers for Windows 10/11. The official **MP Driver Ver. 1.02** for Windows 8.1 x64 works fine, though. Only Canon's installer gets stuck, and printing then fails with **Win32 error 170 ("The requested resource is in use")**.

This one-file script fixes both problems:
- It downloads the **official** Canon package and verifies its Canon signature and SHA-256.
- It installs the printer and scanner drivers with `pnputil`, leaving the driver unmodified.
- It disables bidirectional support, which fixes error 170, and restarts the spooler.
- It prints a test page.
- Its menu also has Repair, Diagnostics, Uninstall and a link to the official Canon page.

**Usage:** plug in the printer via USB, double-click `installa_canon_mp240_win11.cmd`, accept the admin prompt and choose **1**. The messages switch to English automatically on non-Italian Windows.

The Canon driver is not redistributed here. The script downloads it from Canon's own server.

## Licenza / License

MIT. Lo usi a tuo rischio, senza garanzie. Use at your own risk, no warranty. *Canon* e *PIXMA* sono marchi di Canon Inc.; questo progetto non è affiliato a Canon. *Canon* and *PIXMA* are trademarks of Canon Inc.; this project is not affiliated with Canon.
