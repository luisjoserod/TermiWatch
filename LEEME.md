# TermiWatch (versión personalizada)

Fork de [kuglee/TermiWatch](https://github.com/kuglee/TermiWatch), adaptado para
un **Apple Watch Series 9 de 45 mm (watchOS 11)** emparejado con un **iPhone 16 Pro (iOS 18)**,
instalado con una **Apple ID gratuita** (Personal Team).

Historial, decisiones, intentos fallidos e ideas pendientes: [CONTEXTO.md](CONTEXTO.md).

## Qué cambia respecto al original

| Área | Cambio |
| --- | --- |
| Pantalla | Reescrita en SwiftUI (`TerminalView.swift`) y centrada. La pantalla de storyboard original sigue en el proyecto, sin usar. |
| Hora del sistema | Oculta con el modificador privado `._statusBarHidden(true)`. Solo funciona en pantallas SwiftUI. |
| Líneas | `TIME`, `DATE`, `WTHR`, `BATT`, `RING`, `STEP`, `SLEP`, `UPTM` |
| `WTHR` | Open-Meteo (gratis, sin clave). Ubicación fija: **Maracaibo** (10.64, -71.61), sin permiso de ubicación. Formato `29°, Cloud 6%`: temperatura, estado y probabilidad máxima de lluvia en las próximas 3 h. |
| `SLEP` | Último periodo de sueño de Salud, por ejemplo `7h32m`, o `-` si no hay. Deja de consultar en cuanto encuentra el sueño de la mañana. |
| `UPTM` | Tiempo desde la última carga (`up 1d 07h`), estimado al ver el reloj cargando o la batería subir. Se revisa en segundo plano una vez por hora. |
| `RING` | `kcal • min • h`, con espacios. |
| Colores | TIME/BATT/centro de RING en verde neón; DATE/final de RING en azul; SLEP en rojo vivo; UPTM en amarillo. |
| Complicación | ClockKit: icono `$_` para esferas a color y texto `$_` para esferas de un color. Al tocarla se abre la app. |
| Iconos | Borde gris fino, cuadrado a sangre para que watchOS lo recorte en un círculo perfecto (`tools/make_icons.sh`). |
| Batería | Sin GPS; en modo siempre activo redibuja una vez por minuto y sin segundos; consultas solo si los datos están viejos. |
| Firma | Bundle IDs `com.luisjoserod96.*`, Team `7RBUM96B5C`, mínimo watchOS 9. Se quitó HealthKit "Verifiable Health Records", que la cuenta gratuita no permite. |

## Instalación desde cero en un Mac

### 1. Pasos manuales (solo tú puedes hacerlos)
1. Instala **Xcode** desde el App Store.
2. Xcode → Settings → **Accounts** → `+` → inicia sesión con tu Apple ID.
3. Abre `TermiWatch.xcodeproj` una vez, selecciona el target **TermiWatch** → *Signing & Capabilities* → **Team** = tu Personal Team. Así Xcode descarga los datos del equipo.
4. iPhone: **Ajustes → Privacidad y seguridad → Modo de desarrollador** → activar (se reinicia).
5. Apple Watch: **Ajustes → Privacidad y seguridad → Modo de desarrollador** → activar (se reinicia).
6. Conecta el iPhone por cable, desbloquéalo y pulsa **Confiar** en este ordenador.

### 2. Script de instalación
```bash
git clone <este repo> TermiWatch && cd TermiWatch
./tools/setup.sh 7RBUM96B5C        # tu Team ID
```
Instala el servicio que, **al enchufar el iPhone** (si han pasado más de 3 días), compila,
firma e instala la app en el iPhone y en el reloj. Para forzar una instalación ahora:
```bash
zsh ~/Library/Application\ Support/TermiWatchAuto/autoinstall.sh --force
```

### 3. Tras la primera instalación
1. iPhone: **Ajustes → General → VPN y gestión de dispositivos** → tu Apple ID → **Confiar**.
2. Si el reloj no la recibió: app **Watch** del iPhone → TermiWatch → **Instalar**.
3. Abre la app en el reloj y acepta los permisos de **Salud**, incluido Sueño.
4. Complicación: mantén pulsada la esfera → Editar → hueco redondo → TermiWatch.
5. Para que la app siga en pantalla: reloj → **Ajustes → General → Volver a la esfera → Tras 1 hora**.

## Notas
- **Cuenta gratuita:** la firma caduca a los 7 días. El servicio reinstala cada vez que conectas el iPhone y han pasado 3 días o más.
- **Si cambias de Apple ID:** ejecuta `setup.sh` con el nuevo Team ID. Si Xcode dice que el bundle ID ya está en uso, sustituye `com.luisjoserod96` en `TermiWatch.xcodeproj/project.pbxproj` y en los dos `Info.plist` de WatchKit.
- **Si cambias el icono:** quita y vuelve a poner la complicación en la esfera, porque watchOS guarda el icono en caché.
- **Registro:** `~/Library/Application Support/TermiWatchAuto/autoinstall.log`
- **Desactivar el servicio:** `launchctl bootout gui/$(id -u)/com.luisjoserod.termiwatch-autoinstall`
- **Cambiar la ciudad:** `weatherLatitude` / `weatherLongitude` en `TemperatureNotifier.swift`.
