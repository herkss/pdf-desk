const manualEs = <(String, String)>[
  (
    'Primeros pasos',
    '''
PDF Desk maneja los PDF como si fueran papeles extendidos sobre un escritorio.

## La ventana
- Arriba: la barra de menús (`Archivo` `Editar` `Documento` `Ver` `Ayuda`) y la barra de herramientas
- Arriba a la izquierda: las carpetas del escritorio; `Mi escritorio`, arriba del todo, es donde se guardan los documentos
- Abajo a la izquierda: `Este equipo` — Escritorio de Windows, Documentos, Descargas y todas las unidades
- En el centro: el escritorio, con los documentos colocados como hojas de papel
- A la derecha: el panel de vista previa (se muestra u oculta con `Vista previa` en la barra de herramientas)
- Arriba a la derecha: 🎨 tema, 🌐 idioma

## Añadir documentos
- Arrastre PDF o imágenes (jpg, png…) desde el Explorador al escritorio
- `Archivo` → `Importar archivos…` o `Ctrl+O`
- Imprima desde cualquier programa en la impresora `PDF Desk`
- Clic derecho en el escritorio → `Nuevo documento…` (`Ctrl+N`) para un documento en blanco

## La carpeta del escritorio
Los documentos son archivos normales en `C:\\Users\\<nombre>\\PdfDesk`. Puede cambiarla en `Configuración`.
''',
  ),
  (
    'Trabajar en el escritorio',
    '''
## Mover y seleccionar
- Arrastre un documento a cualquier lugar; el que pulse pasa a estar encima
- Arrastre sobre un espacio vacío para seleccionar un área, `Ctrl`/`Shift`+clic para varios, `Ctrl+A` para todos
- Con dos o más seleccionados aparece encima una barra `Apilar · Desplegar · Carpeta`
- Arrastre con el botón central para mover todo el escritorio

## Zoom
- `Ctrl`+rueda agranda o reduce los documentos alrededor del ratón
- El control deslizante de la barra de estado y el menú `Ver` hacen lo mismo

## Copiar
- Seleccione documentos y arrástrelos con `Ctrl` pulsado: se colocan copias (aparece un `+` verde)
- `Ctrl+D` duplica

## Más
- Doble clic abre el visor
- `F2` cambiar nombre, `Del` eliminar (a la papelera); todos los comandos están también en el menú del clic derecho
- `Ordenar` alinea los documentos por nombre o por fecha
''',
  ),
  (
    'Apilar · Desplegar · Carpeta',
    '''
## Apilar (combinar)
- Suelte un documento sobre otro y sus páginas se añaden al instante tras las de ese documento
- Puede seguir apilando sobre el documento combinado tantas veces como quiera
- `Deshacer`, abajo, revierte el último apilado
- Mantenga `Shift` al soltar para solo colocarlo encima
- Seleccione varios y pulse `Apilar` para combinarlos en el orden de selección

## Desplegar
- Divide un documento de varias páginas en una hoja por página, colocadas una al lado de otra
- Vuelva a apilar las hojas para unirlas de nuevo
- `Dividir (conservar original)` crea un documento por página y conserva el original

## Carpetas
- Agrupe documentos manteniendo cada uno por separado (en el visor aparecen como pestañas)
- Suelte documentos sobre una carpeta para añadirlos; `Deshacer carpeta` los separa
''',
  ),
  (
    'Este equipo y carpetas',
    '''
## Carpetas del escritorio (arriba a la izquierda)
- Pulse una carpeta para abrir su escritorio
- Suelte documentos del escritorio sobre una carpeta para moverlos allí
- Clic derecho: nueva carpeta, cambiar nombre, eliminar

## Este equipo (abajo a la izquierda)
- Explore el Escritorio de Windows, Documentos, Descargas y unidades como C: y D:
- Pulse una carpeta para ver sus subcarpetas y sus archivos PDF e imágenes
- Arrastre un PDF o una imagen del disco al escritorio para moverlo dentro (`Ctrl`: copiar)
- Arrastre documentos del escritorio a una carpeta del disco para copiarlos fuera; las anotaciones quedan grabadas y una carpeta se convierte en un solo PDF
- Arrastre un archivo a otra carpeta del disco para moverlo (`Ctrl`: copiar)
- Clic derecho en una carpeta → `Abrir como escritorio` para trabajar directamente en ella
- Arrastre el encabezado `Este equipo` hacia arriba o abajo para repartir la altura
''',
  ),
  (
    'Visor y anotaciones',
    '''
Haga doble clic en un documento para abrir el visor. Las anotaciones se guardan aparte y el PDF original no cambia.

## Herramientas de dibujo
- Lápiz, resaltador, línea, flecha, rectángulo, elipse, texto, nota adhesiva, sello de fecha, borrador
- `Shift`+arrastrar: líneas de 45°, cuadrados, círculos
- La herramienta de selección mueve, el tirador de la esquina cambia el tamaño, el doble clic edita el texto

## Propiedades
Seleccione una anotación, clic derecho → `Propiedades…`
- Color de línea, grosor, tipo (continua, discontinua, punteada, raya-punto), puntas de flecha
- Color de fondo y opacidad (las formas pueden tener fondo y ninguna línea)
- Fuente, tamaño, negrita, cursiva, color del texto
- 🎨: una paleta de 126 colores, colores recientes o un código `#RRGGBB`

## Páginas
En la lista de páginas de la izquierda: arrastre para reordenar, gire, elimine, extraiga, inserte archivos

## Buscar y ver
`Ctrl+F` buscar, `F3` siguiente, `Ctrl+rueda` zoom, `Ctrl+0` ajustar al ancho
''',
  ),
  (
    'Copiar una región',
    '''
Recorte parte de una página y péguela en otro documento.

## Cómo
- Elija `Copiar región` (las tijeras) en la barra del visor
- Arrastre un recuadro alrededor de la parte que quiere copiar
- Abra otro documento (u otra página) y pulse `Ctrl+V`, o clic derecho → `Pegar`
- La imagen pegada se mueve y cambia de tamaño como cualquier anotación

## Conviene saber
- Las anotaciones que haya dentro del recuadro forman parte de la imagen
- El texto del recuadro también va al portapapeles de Windows, para el Bloc de notas, Word, etc.
- Al exportar o imprimir, la imagen pegada se conserva en el PDF
''',
  ),
  (
    'Imprimir y la impresora PDF Desk',
    '''
## La impresora PDF Desk
Imprima desde cualquier programa (Word, Excel, un navegador…) y el documento aparece en el escritorio, sin cuadro de guardar.
- Elija `Instalar` en el aviso del primer inicio, o `Archivo` → `Configurar la impresora 'PDF Desk'…`
- Confirme la solicitud de administrador (UAC); pasa a ser la impresora predeterminada
- No se instala ningún controlador: usa el "Microsoft Print to PDF" de Windows
- Si elige el "Microsoft Print to PDF" normal, se le pedirá dónde guardar y no llegará al escritorio

## Exportar e imprimir
- `Exportar PDF`: un PDF con las anotaciones grabadas, que se ve igual en cualquier visor
- `Imprimir` (`Ctrl+P`): imprime con las anotaciones
''',
  ),
  (
    'Papelera y deshacer',
    '''
## Papelera
- Los documentos eliminados van primero a la papelera (se guardan 30 días)
- `Deshacer`, justo después de eliminar, los recupera
- `Archivo` → `Papelera…` para `Restaurar`, `Eliminar definitivamente` o `Vaciar papelera`

## Deshacer
- Apilar: `Deshacer` en la parte inferior
- Anotaciones en el visor: `Ctrl+Z` deshacer, `Ctrl+Y` rehacer
- Los cambios hechos en el cuadro de propiedades se deshacen con un solo `Ctrl+Z`
''',
  ),
  (
    'Temas e idiomas',
    '''
## Temas
Elija uno con 🎨 arriba a la derecha: iOS claro, iOS oscuro, Clásico (DocuWorks), Papel (sepia), Bosque, Medianoche

## Idiomas
Elija uno con 🌐 arriba a la derecha: 한국어, 日本語, 中文, English, Español, Français

Ambos se recuerdan para la próxima vez.
''',
  ),
  (
    'Atajos de teclado',
    '''
## Escritorio
- `Ctrl+N` nuevo documento, `Ctrl+O` importar, `Ctrl+P` imprimir
- `Ctrl+A` seleccionar todo, `Ctrl+D` duplicar, `F2` cambiar nombre, `Del` eliminar
- `Ctrl+F` buscar nombres, `F5` actualizar, `F1` manual
- `Ctrl`+rueda zoom, `Ctrl`+arrastrar copiar, `Shift`+soltar colocar encima sin apilar
- Vista previa: `←` `→` `PageUp` `PageDown`

## Visor
- `Ctrl+Z` / `Ctrl+Y` deshacer / rehacer
- `Ctrl+C` / `Ctrl+V` copiar / pegar anotaciones y regiones
- `Ctrl+F` buscar, `F3` / `Shift+F3` siguiente / anterior
- `Ctrl+rueda`, `Ctrl +`, `Ctrl -` zoom, `Ctrl+0` ajustar al ancho
- `Esc` herramienta de selección, `Del` eliminar las anotaciones seleccionadas
''',
  ),
  (
    'Solución de problemas',
    '''
## "El archivo está en uso y no se pudo procesar"
- Si la carpeta del escritorio está dentro de OneDrive, los archivos se bloquean mientras se sincronizan
- Cuando aparezca `Mover la carpeta del escritorio` al iniciar, elija `Mover` (a C:\\Users\\<nombre>\\PdfDesk)
- Cierre el documento si otro visor de PDF lo tiene abierto e inténtelo de nuevo

## Lo impreso no llega al escritorio
- Compruebe que la impresora del cuadro de impresión sea `PDF Desk`
- PDF Desk debe estar abierto para colocar el documento en el escritorio

## Este equipo no muestra nada
- Compruebe que no lo haya plegado con la flecha a la derecha del título `Este equipo`
- Pulse una carpeta para ver su contenido. Una carpeta sin PDF ni imágenes dice "No hay archivos PDF ni de imagen"

## Una fuente se ve distinta
- La fuente debe estar instalada en el equipo para incluirse en el PDF; si no, se usa Malgun Gothic
''',
  ),
];
