# Contexto del proyecto

Este documento resume cómo se llegó a esta versión de TermiWatch: qué se probó, qué funcionó,
qué no y por qué. Sirve para retomar el trabajo más adelante, tú o un asistente de IA.
La instalación paso a paso está en [LEEME.md](LEEME.md).

**Entorno de referencia (noviembre 2026):** macOS 15.8, Xcode 26.3 (SDK iOS/watchOS 26.2),
iPhone 16 Pro con iOS 18.7, Apple Watch Series 9 de 45 mm con watchOS 11.6, Apple ID gratuita.

---

## 1. Objetivo

- Instalar TermiWatch, una "esfera" de terminal para Apple Watch de 2018–2020, en un reloj actual.
- Que se renueve sola, **por cable o por Wi-Fi**, porque con una cuenta gratuita la firma caduca a los 7 días.
- Personalizar su aspecto y sus datos sin gastar batería.

TermiWatch **no es una esfera real**: Apple no permite esferas de terceros. Es una app que
imita una esfera, y se abre desde una complicación o con "Volver a la esfera → Tras 1 hora".

---

## 2. Instalación y firma: problemas encontrados

| Problema | Causa | Solución |
| --- | --- | --- |
| `xcodebuild` no funciona | Solo estaban las Command Line Tools | Instalar Xcode. Los scripts usan `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`, así que no hace falta `sudo xcode-select`. |
| "iOS 26.2 is not installed" | Desde Xcode 15, compilar para un dispositivo real exige el paquete de la plataforma, que incluye el simulador | `xcodebuild -downloadPlatform iOS -architectureVariant arm64` y lo mismo para `watchOS` (unos 11 GB en total). watchOS es obligatorio porque la app incrusta la del reloj. No hacen falta los simuladores creados (`xcrun simctl delete all`). |
| No aparece el Team | Xcode no había descargado los datos de la cuenta | Elegir el Team una vez en la interfaz de Xcode (Signing & Capabilities) |
| "Developer Mode disabled" | El iPhone no tenía activado el modo desarrollador | Ajustes → Privacidad y seguridad → Modo de desarrollador |
| "Personal development teams… do not support HealthKit Access (Verifiable Health Records)" | Los entitlements incluían `com.apple.developer.healthkit.access` vacío | Eliminar esa clave y dejar solo `com.apple.developer.healthkit` |
| "Your team has no devices…" para la app del reloj | El reloj no estaba registrado (modo desarrollador apagado, "no DDI") | Activar el modo desarrollador en el reloj y compilar una vez el esquema *WatchKit App* con `-destination id=<UDID del reloj> -allowProvisioningDeviceRegistration` |
| "Cannot install… not from a trusted developer" en la app Watch | iOS no confiaba en el certificado | iOS 18: Ajustes → General → **VPN y gestión de dispositivos** (ya no se llama "Perfiles") → Confiar |
| `devicectl install` al reloj: "Timed out… establish tunnel" | El Mac llega al reloj por Wi-Fi; con la pantalla apagada se corta | Reloj despierto, en el cargador y en la misma red. Alternativa: instalar desde la app Watch del iPhone. |
| Reloj en "Disconnected": "The device rejected the connection request" / "may need to be unlocked to recover from previously reported preparation errors" | Tras muchos intentos fallidos con el reloj dormido, la confianza de desarrollo entre el Mac y el reloj queda inválida. **No** era NordVPN (funciona con la VPN activa) ni faltaba ningún componente. | `xcrun devicectl manage pair --device <UDID del reloj>` con el reloj desbloqueado; después `tunnelState: connected`. `autoinstall.sh` lo hace solo entre reintentos. |
| La app Watch del iPhone: "This app could not be installed at this time" | **Restricción de Apple:** watchOS rechaza las apps firmadas con perfil **gratuito** cuando llegan desde el iPhone. Error real en el registro del iPhone (`sudo log collect --device-name …`, proceso `appconduitd`): `MIInstallerErrorDomain Code=111 … authorized by a free provisioning profile, but apps validated by those are not allowed to be installed from this source` | Con cuenta gratuita, el reloj **solo** se puede instalar directamente desde el Mac (`devicectl device install app` o Xcode). La única alternativa es la cuenta de pago. Nunca desactivar "Mostrar app en el Apple Watch": no se puede reinstalar desde el iPhone. |
| Icono de TermiWatch atascado en "Instalando" en el reloj | Instalación fallida desde el iPhone (ver fila anterior) | `xcrun devicectl device uninstall app --device <UDID del reloj> com.luisjoserod96.TermiWatch.watchkitapp` |
| `git bundle` falla | El repositorio era un clon superficial (`--depth 1`) | `git fetch --unshallow` |

- **Bundle IDs:** `com.kuglee.*` se cambió a `com.luisjoserod96.*`. Las dependencias SPM del autor (`PMKHealthKit`, `Swizzle`) siguen apuntando a sus repositorios.
- **Número de compilación:** `CFBundleVersion = $(CURRENT_PROJECT_VERSION)` en los tres `Info.plist`. `autoinstall.sh` pasa `CURRENT_PROJECT_VERSION=AAAAMMDDhhmm`, así que cada instalación es una versión nueva. El proyecto trae `1` por defecto.
- **Mínimo watchOS:** se subió de 5.0 a 9.0, necesario para las APIs de ClockKit de la complicación y para `HKCategoryValueSleepAnalysis.allAsleepValues`.

---

## 3. Auto-instalación (`tools/autoinstall.sh` + launchd)

- Un *LaunchAgent* ejecuta el script cada 10 s. Comprobar `ioreg -p IOUSB` no cuesta casi nada.
- **Por cable:** al detectar una **conexión nueva** de un iPhone, si han pasado **3 días o más** desde la última instalación.
- **Por Wi-Fi:** una vez por hora, si han pasado **4 días o más** y `devicectl` ve el iPhone emparejado en la red local (`available (paired)`). Con el cable desenchufado se compila e instala igual.
- Si el reloj no responde (dormido o sin Wi-Fi), se crea `.watch_pending` y se reintenta **solo el reloj** cada hora hasta conseguirlo, porque la app del reloj también caduca a los 7 días.
- En los dos casos:
  1. `xcodebuild` con firma automática (`-allowProvisioningUpdates -allowProvisioningDeviceRegistration`).
  2. `devicectl device install app` en el iPhone.
  3. `devicectl device install app` directamente en el reloj, con `Watch/TermiWatch WatchKit App.app`. El iPhone tardaba en pasarla por su cuenta.
  4. Notificación en el Mac con `osascript`.
- `--force` instala ya, por cable si está conectado o, si no, por Wi-Fi.
- Se usa un candado (`.lock`) para evitar ejecuciones dobles. **Si el script se interrumpe a la fuerza, el candado puede quedarse** y hay que borrarlo a mano: `rmdir ~/Library/Application\ Support/TermiWatchAuto/.lock`.
- `devicectl list devices` usa identificadores de CoreDevice, pero `xcodebuild -destination id=` necesita el **UDID de hardware**. El script lo saca de `--json-output` → `hardwareProperties.udid`.

---

**Estado (16 nov 2026):** el servicio automático se **desactivó** a petición del usuario. Las instalaciones
se hacen a mano con `autoinstall.sh --force`. Motivo: sus intentos cada hora con el reloj dormido acababan
invalidando la confianza entre el Mac y el reloj o dejando instalaciones atascadas.

## 4. Ocultar la hora del sistema (lo más difícil)

En watchOS 10 y posteriores, la hora de arriba a la derecha aparece sobre cualquier app de terceros.
Apple dice oficialmente que no se puede ocultar.

| Intento | Resultado en watchOS 11 |
| --- | --- |
| Truco original del autor: escena SpriteKit oculta y `SPFullScreenView.timeLabel` o *swizzle* de `CLKTimeFormatter` (watchOS 5/6) | No funciona |
| `PUICApplication._setStatusBarTimeHidden:animated:` (variante del autor para watchOS 7) | No funciona |
| `PUICApplication._setStatusBarTimeHidden:animated:completion:` (ejemplo *AnalogFace*, que funcionaba en watchOS 9) | El método existe, pero el sistema **lo ignora**: `_isStatusBarTimeHidden` sigue en `false` |
| `PUICStatusBar setHidden:` / `alpha = 0` / ocultar su `UIStatusBarWindow` | La barra dentro de la app queda marcada como oculta, pero **la hora sigue viéndose**: la dibuja otra capa |
| **Rehacer la pantalla en SwiftUI con `._statusBarHidden(true)`** | ✅ **Funciona** |

- `.statusBarHidden()` está marcado como *unavailable* en watchOS. `._statusBarHidden()`, con guion bajo, sí compila (`@available(watchOS 6.0, *)`) y funciona.
- **Solo tiene efecto en pantallas SwiftUI** (`WKHostingController`), no en pantallas de storyboard WatchKit. Por eso se reescribió la pantalla en `TerminalView.swift`.
- Es una API semiprivada: un SDK futuro podría romperlo.
- El storyboard tiene ahora como pantalla inicial `TerminalHostingController`. La pantalla antigua, `InterfaceController`, sigue en el proyecto sin usarse; sirve de respaldo y se puede borrar.

Para investigar se volcaron selectores y la jerarquía de vistas a `Documents/` en el reloj y se
descargaron con `xcrun devicectl device copy from --domain-type appDataContainer`.

---

## 5. Diseño de la pantalla

```
user@watch:~ $ now
[TIME]12:28:46 AM          verde neón (sin segundos en modo siempre activo)
[DATE]Nov 16, Mon          azul
[WTHR]29°, Cloud 6%        naranja
[BATT][####.] 80%          verde neón (rojo ≤ 20 %)
[RING]8 • 0 • 0            rojo • verde neón • azul (kcal • min • h)
[STEP]0 steps              morado
[SLEP]7h32m                cian
user@watch:~ $
```

- Las etiquetas tienen siempre **4 letras** para que el texto quede alineado.
- Letra monoespaciada del sistema (equivale a SF Mono). El tamaño se calcula como `ancho_pantalla / 12.4`, 16 pt en 45 mm.
- El bloque se **centra** en vertical y en horizontal, con el texto alineado a la izquierda.
- Cada línea es un único `Text` concatenado, con `lineLimit(1)` y `minimumScaleFactor(0.7)`: si una línea no cabe, encoge esa línea en vez de cortarse.
- Caben unas **10 líneas** y unos **19 caracteres** por línea en 45 mm.
- Los colores de RING y de TIME/DATE se unificaron a petición del usuario.

---

## 6. Datos y por qué así

### WTHR, el tiempo
- El original usaba OpenWeatherMap con la clave del autor. La clave seguía funcionando, pero la app solo consultaba al arrancar y luego cada 10 minutos, así que tras conceder el permiso de ubicación seguía mostrando `--`.
- Ahora usa **Open-Meteo**: gratis, sin clave, y en **una sola petición** da la temperatura, el código WMO y la probabilidad de lluvia por hora.
- **Ubicación fija: Maracaibo** (10.64, -71.61). Se eliminó CoreLocation y el permiso de ubicación.
- Formato C, elegido por el usuario: `29°, Cloud 6%`.
  - Estado: código WMO convertido a palabras de 5 letras como máximo: Clear, Cloud, Fog, Rain, Snow, Storm.
  - Lluvia: el máximo de las próximas 3 horas.
- **Descartado:** WeatherKit (la app Tiempo de Apple) requiere una cuenta de pago. La temperatura de la muñeca no está disponible en tiempo real; HealthKit solo da la variación nocturna.

### SLEP, el sueño
- Sustituye a L_HR (pulso), que el usuario tiene apagado para ahorrar batería.
- Lee `sleepAnalysis` de las últimas 36 h, solo los valores de "dormido" (core, profundo, REM y sin especificar). Fusiona los solapamientos entre fuentes y agrupa en sesiones; una pausa de más de 3 h abre una sesión nueva. Muestra la última sesión o `-`.
- Se actualiza al momento con un `HKObserverQuery` sobre `sleepAnalysis`, en cuanto el reloj guarda una sesión de sueño. Además, mientras muestra `-` consulta en cada activación, y si no, como mucho cada 30 minutos.
- **Deja de consultar hasta el día siguiente** cuando el sueño terminó hoy y hace al menos 2 h.
- Si sale `-`, lo habitual es que no haya registro: el reloj estaba cargando o el seguimiento del sueño estaba apagado.

### UPTM (eliminado)
- Mostraba el tiempo desde la última carga, estimado al ver el reloj cargando o la batería subir, con una revisión en segundo plano cada hora. Se quitó porque al usuario no le gustaba, y con él se fue la tarea en segundo plano.

### RING y STEP
- Un único `HKObserverQuery`, sobre la energía activa, refresca el resumen de anillos completo.
- STEP usa la estadística del día de `stepCount`, como el original.

---

## 7. Ahorro de batería

- Sin GPS ni permiso de ubicación.
- **Modo siempre activo** (`isLuminanceReduced`): redibuja una vez por minuto y sin segundos. Con la muñeca levantada, una vez por segundo.
- Sin temporizador del tiempo: solo al abrir o volver a la app, y solo si el dato tiene más de 30 minutos.
- La batería se lee cada 5 minutos con la app abierta y al volver a ella.
- La complicación es estática (`timelineEndDate = .distantFuture`) y **no se recarga** en cada arranque.
- **Descartado:** mantener la app siempre abierta con una sesión de entrenamiento falsa (`HKWorkoutSession`, el truco de *AnalogFace*). Gasta mucha batería y ensucia los datos de Actividad. Lo recomendado es *Ajustes → General → Volver a la esfera → Tras 1 hora*.

---

## 8. Complicación e iconos

- Complicación **ClockKit** (`ComplicationController.swift`). Está obsoleta desde watchOS 10, pero funciona y no exige reestructurar el proyecto, cosa que WidgetKit sí haría.
  - Esferas a color: imagen `ComplicationIcon`.
  - Esferas de un solo color: texto `$_`.
- En la esfera puede haber **dos opciones de TermiWatch**: el acceso directo que watchOS crea solo, que usa el **icono de la app**, y la complicación ClockKit.
- **watchOS guarda en caché** las imágenes de las complicaciones: tras cambiar un icono hay que quitar y volver a poner la complicación.
- Iconos (`tools/make_icons.sh`):
  - El original tenía un aro blanco grueso y un círculo que tocaba el borde de la imagen, lo que dejaba "píxeles raros" en los puntos cardinales.
  - Ahora los iconos de la app son un **cuadrado a sangre**: fondo gris hasta las esquinas y disco negro dentro. watchOS aplica su máscara circular y queda un aro gris fino perfecto.
  - La complicación usa un círculo con un margen transparente.
  - Se generan a 1024 px con Swift/AppKit y se reducen con interpolación alta.

---

## 9. Ideas pendientes (no implementadas)

- **Sin coste:** `[SUN ]` próximo amanecer o atardecer, `[DAYL]` horas de luz, `[DAY%]` o `[YEAR]` progreso con barra, `[MOON]` fase lunar, `[UTC ]` otra zona horaria, `[WEEK]` semana y día del año, `[CNTD]` cuenta atrás.
- **Misma consulta del tiempo:** `[HUMI]` humedad, `[FEEL]` sensación térmica, `[WIND]` viento.
- **Desde Salud:** `[STRK]` racha de anillos cerrados, `[DIST]` distancia, `[FLRS]` pisos, `[MIND]` minutos de mindfulness.
- **Con una consulta extra:** `[UVI ]` índice UV, `[AQI ]` calidad del aire.
- **Otras:** `[NEXT]` próximo evento del calendario (EventKit), interruptor opcional de sesión de entrenamiento para mantener la app abierta.
- **Limpieza:** borrar `InterfaceController` y su escena del storyboard; quitar las dependencias `PMKCoreLocation` y `Swizzle`, que ya no se usan; migrar la complicación a WidgetKit si ClockKit deja de funcionar.

---

## 10. Repositorio

- Fork público: `luisjoserod/TermiWatch`, con la rama por defecto `maracaibo-custom`. La rama `master` es igual al original.
- Remotos: `origin` es el fork y `upstream` es `kuglee/TermiWatch`.
- Respaldo local: `~/Documents/TermiWatch-respaldo/TermiWatch.bundle`. Para clonarlo: `git clone -b maracaibo-custom <bundle>`.
