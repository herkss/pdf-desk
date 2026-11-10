import 'l10n.dart';

/// The user manual: (chapter title, body) per language. Body markup: `## `
/// subheading, `- ` bullet, `` `key` `` for keys and buttons. Languages
/// without their own text use the English one.
List<(String, String)> manualFor(AppLanguage lang) => lang == AppLanguage.ko ? _ko : _en;

const _ko = <(String, String)>[
  (
    '시작하기',
    '''
PDF Desk는 종이 문서를 책상 위에 펼쳐 놓고 일하듯 PDF를 다루는 프로그램입니다.

## 화면 구성
- 위: 메뉴 막대(`파일` `편집` `문서` `표시` `도움말`)와 도구 막대
- 왼쪽 위: 데스크 폴더 트리. 맨 위 `내 데스크`가 문서 보관 폴더입니다
- 왼쪽 아래: `내 PC` — 바탕 화면, 문서, 다운로드와 모든 드라이브
- 가운데: 데스크. 문서가 종이처럼 놓입니다
- 오른쪽: 미리보기 창 (도구 막대의 `미리보기`로 켜고 끔)
- 오른쪽 위: 🎨 테마, 🌐 언어

## 문서 넣기
- 탐색기에서 PDF나 이미지(jpg, png 등)를 데스크로 끌어다 놓기
- `파일` → `파일 가져오기…` 또는 `Ctrl+O`
- 다른 프로그램에서 `PDF Desk` 프린터로 인쇄
- 데스크 빈 곳 우클릭 → `새 문서 작성…`(`Ctrl+N`)으로 빈 문서 만들기

## 데스크 폴더
문서는 `C:\\Users\\이름\\PdfDesk`에 실제 파일로 저장됩니다. `환경 설정`에서 바꿀 수 있습니다.
''',
  ),
  (
    '데스크 다루기',
    '''
## 옮기기와 선택
- 문서를 끌어서 원하는 곳에 놓습니다. 클릭한 문서가 맨 위로 올라옵니다
- 빈 곳을 끌면 범위 선택, `Ctrl`/`Shift`+클릭으로 여러 개 선택, `Ctrl+A` 모두 선택
- 2개 이상 선택하면 바로 위에 `겹치기 · 펼치기 · 바인더` 막대가 뜹니다
- 가운데 버튼으로 끌면 데스크 전체가 움직입니다

## 확대·축소
- `Ctrl`+마우스 휠: 마우스 위치를 기준으로 문서 크기를 키우고 줄입니다
- 아래 상태 막대의 슬라이더나 `표시` 메뉴로도 바꿀 수 있습니다

## 복사
- 문서를 선택하고 `Ctrl`을 누른 채 끌어 놓으면 그 자리에 복사본이 생깁니다 (초록색 `+` 표시)
- `Ctrl+D`: 복제

## 그 밖에
- 더블클릭: 뷰어로 열기
- `F2` 이름 바꾸기, `Del` 삭제(휴지통으로), 우클릭 메뉴에 모든 명령이 있습니다
- `정렬`: 이름순/수정일순으로 가지런히
''',
  ),
  (
    '겹치기 · 펼치기 · 바인더',
    '''
## 겹치기 (합치기)
- 문서를 다른 문서 위에 끌어다 놓으면 바로 그 문서 뒤에 페이지가 붙습니다
- 합친 문서를 또 다른 문서에 계속 겹칠 수 있습니다
- 아래에 뜨는 `실행 취소`로 직전 겹치기를 되돌립니다
- `Shift`를 누른 채 놓으면 합치지 않고 위에 올려놓기만 합니다
- 여러 개를 선택하고 `겹치기`를 누르면 선택한 순서대로 합칩니다

## 펼치기
- 여러 장짜리 문서를 한 장씩 낱장 문서로 나눠 나란히 펼칩니다
- 펼친 낱장은 다시 겹치기로 합칠 수 있습니다
- `분할 (원본 유지)`은 원본을 남겨 둔 채 페이지별 문서를 만듭니다

## 바인더
- 여러 문서를 하나로 묶되 각각의 문서를 유지합니다 (뷰어에서 탭으로 표시)
- 바인더 위에 문서를 놓으면 추가되고, `바인더 해제`로 다시 풉니다
''',
  ),
  (
    '내 PC와 폴더',
    '''
## 데스크 폴더 트리 (왼쪽 위)
- 폴더를 클릭하면 그 폴더의 데스크가 열립니다
- 데스크 문서를 폴더로 끌어다 놓으면 그 폴더로 옮겨집니다
- 우클릭: 새 폴더, 이름 바꾸기, 삭제

## 내 PC (왼쪽 아래)
- 바탕 화면, 문서, 다운로드와 C:, D: 같은 드라이브를 탐색기처럼 펼쳐 봅니다
- 디스크의 PDF·이미지를 데스크로 끌면 데스크로 옮겨집니다 (`Ctrl`: 복사)
- 데스크 문서를 디스크 폴더로 끌면 복사됩니다. 주석은 PDF에 새겨지고 바인더는 한 PDF가 됩니다
- 파일을 다른 디스크 폴더로 끌면 옮겨집니다 (`Ctrl`: 복사)
- 폴더 우클릭 → `데스크로 열기`: 그 폴더를 바로 데스크로 씁니다
- `내 PC` 제목줄을 위아래로 끌어 두 영역의 높이를 나눕니다
''',
  ),
  (
    '뷰어와 주석',
    '''
문서를 더블클릭하면 뷰어가 열립니다. 주석은 원본과 따로 저장되어 원본 PDF는 바뀌지 않습니다.

## 그리기 도구
- 펜, 형광펜, 직선, 화살표, 사각형, 타원, 텍스트, 부전(메모), 날짜 도장, 지우개
- `Shift`+끌기: 45° 직선, 정사각형, 정원
- 선택 도구로 옮기고, 모서리 핸들로 크기 조절, 더블클릭으로 글자 편집

## 속성 바꾸기
주석을 선택하고 우클릭 → `속성…`
- 선 색, 굵기, 선 종류(실선·파선·점선·일점쇄선), 화살표 시작점/끝점
- 배경색과 불투명도 (사각형·타원은 선 없이 배경만도 가능)
- 글꼴, 크기, 굵게, 기울임, 글자색
- 🎨 버튼: 126색 팔레트, 최근 사용한 색, `#RRGGBB` 직접 입력

## 페이지 편집
왼쪽 페이지 목록에서 끌어서 순서 변경, 회전, 삭제, 추출, 파일 삽입

## 검색과 보기
`Ctrl+F` 문서 안 검색, `F3` 다음, `Ctrl+휠` 확대·축소, `Ctrl+0` 폭 맞춤
''',
  ),
  (
    '영역 복사와 붙여 넣기',
    '''
문서의 일부분을 잘라서 다른 문서에 붙여 넣을 수 있습니다.

## 사용 방법
- 뷰어 도구 막대에서 `영역 복사`(가위 아이콘)를 고릅니다
- 복사할 부분을 마우스로 끌어 상자로 지정합니다
- 다른 문서(또는 다른 페이지)를 열고 `Ctrl+V` 또는 우클릭 → `붙여넣기`
- 붙여 넣은 그림은 다른 주석처럼 옮기고 크기를 바꿀 수 있습니다

## 알아 두기
- 영역 안에 있던 주석도 함께 그림에 들어갑니다
- 영역 안의 글자는 Windows 클립보드에도 복사되어 메모장, 워드 등에 붙여 넣을 수 있습니다
- PDF로 내보내거나 인쇄하면 붙여 넣은 그림도 PDF 안에 들어갑니다
''',
  ),
  (
    '인쇄와 PDF Desk 프린터',
    '''
## PDF Desk 프린터
다른 프로그램(워드, 엑셀, 브라우저…)에서 인쇄하면 저장 창 없이 문서가 데스크에 바로 놓입니다.
- 처음 실행할 때 뜨는 안내에서 `설치`, 또는 `파일` → `'PDF Desk' 프린터 설치/설정…`
- 관리자 권한 확인(UAC)에 `예`를 누르면 끝납니다. 기본 프린터로 지정됩니다
- 따로 드라이버를 깔지 않고 Windows에 있는 "Microsoft Print to PDF"를 이용합니다
- 인쇄 창에서 일반 "Microsoft Print to PDF"를 고르면 저장 위치를 묻고 데스크로 오지 않습니다

## 내보내기와 인쇄
- `PDF 내보내기`: 주석을 새겨 넣은 PDF로 저장 (다른 PDF 뷰어에서도 똑같이 보임)
- `인쇄`(`Ctrl+P`): 주석까지 함께 인쇄
''',
  ),
  (
    '휴지통과 되돌리기',
    '''
## 휴지통
- 삭제한 문서는 바로 지워지지 않고 휴지통으로 갑니다 (30일 보관)
- 삭제 직후 아래에 뜨는 `실행 취소`로 되돌립니다
- `파일` → `휴지통…`에서 골라 `복원`하거나 `영구 삭제`, `휴지통 비우기`

## 되돌리기
- 겹치기: 아래에 뜨는 `실행 취소`
- 뷰어의 주석: `Ctrl+Z` 실행 취소, `Ctrl+Y` 다시 실행
- 주석 속성 창에서 바꾼 것은 `Ctrl+Z` 한 번에 되돌아갑니다
''',
  ),
  (
    '테마와 언어',
    '''
## 테마
오른쪽 위 🎨에서 고릅니다: iOS 라이트, iOS 다크, 클래식(DocuWorks), 종이(세피아), 포레스트, 미드나이트

## 언어
오른쪽 위 🌐에서 고릅니다: 한국어, 日本語, 中文, English, Español, Français

고른 테마와 언어는 저장되어 다음에도 그대로 열립니다.
''',
  ),
  (
    '단축키',
    '''
## 데스크
- `Ctrl+N` 새 문서, `Ctrl+O` 가져오기, `Ctrl+P` 인쇄
- `Ctrl+A` 모두 선택, `Ctrl+D` 복제, `F2` 이름 바꾸기, `Del` 삭제
- `Ctrl+F` 이름 검색, `F5` 새로 고침, `F1` 사용 설명서
- `Ctrl`+휠 확대·축소, `Ctrl`+끌기 복사, `Shift`+놓기 겹치지 않고 올려놓기
- 미리보기: `←` `→` `PageUp` `PageDown`

## 뷰어
- `Ctrl+Z` / `Ctrl+Y` 실행 취소 / 다시 실행
- `Ctrl+C` / `Ctrl+V` 주석·영역 복사 / 붙여넣기
- `Ctrl+F` 검색, `F3` / `Shift+F3` 다음 / 이전
- `Ctrl+휠`, `Ctrl +`, `Ctrl -` 확대·축소, `Ctrl+0` 폭 맞춤
- `Esc` 선택 도구, `Del` 선택한 주석 삭제
''',
  ),
  (
    '문제 해결',
    '''
## "파일을 사용 중이라 처리하지 못했습니다"
- 데스크 폴더가 OneDrive 안에 있으면 동기화하는 동안 파일이 잠깁니다
- 시작할 때 `데스크 폴더 옮기기` 창이 뜨면 `옮기기`를 누르세요 (C:\\Users\\이름\\PdfDesk로 옮김)
- 같은 문서를 다른 PDF 뷰어에서 열어 두었다면 닫고 다시 시도하세요

## 인쇄해도 데스크에 오지 않아요
- 인쇄 창에서 프린터가 `PDF Desk`인지 확인하세요
- PDF Desk가 켜져 있어야 데스크에 놓입니다

## 글꼴이 다르게 나와요
- 고른 글꼴이 PC에 설치되어 있어야 PDF에 들어갑니다. 없으면 맑은 고딕으로 나옵니다
''',
  ),
];

const _en = <(String, String)>[
  (
    'Getting started',
    '''
PDF Desk handles PDFs the way you handle paper on a desk.

## The window
- Top: the menu bar (`File` `Edit` `Document` `View` `Help`) and the toolbar
- Top left: the desk folders; `My desk` at the top is where documents are kept
- Bottom left: `This PC` — Desktop, Documents, Downloads and every drive
- Centre: the desk, with documents lying on it like sheets of paper
- Right: the preview pane (toggle it with `Preview` on the toolbar)
- Top right: 🎨 theme, 🌐 language

## Adding documents
- Drag PDFs or images (jpg, png, …) from Explorer onto the desk
- `File` → `Import files…` or `Ctrl+O`
- Print from any program to the `PDF Desk` printer
- Right-click the desk → `New document…` (`Ctrl+N`) for a blank document

## The desk folder
Documents are ordinary files in `C:\\Users\\<name>\\PdfDesk`. You can change it in `Settings`.
''',
  ),
  (
    'Working on the desk',
    '''
## Moving and selecting
- Drag a document anywhere; the one you click comes to the top
- Drag over empty space to select a range, `Ctrl`/`Shift`+click to select several, `Ctrl+A` for all
- With two or more selected, a `Stack · Spread · Binder` bar appears above them
- Drag with the middle button to move the whole desk

## Zoom
- `Ctrl`+wheel makes documents larger or smaller around the mouse
- The slider in the status bar and the `View` menu do the same

## Copying
- Select documents and drag them with `Ctrl` held: copies are laid down (a green `+` shows)
- `Ctrl+D` duplicates

## More
- Double-click opens the viewer
- `F2` rename, `Del` delete (to the trash); every command is also on the right-click menu
- `Arrange` lines documents up by name or date
''',
  ),
  (
    'Stack · Spread · Binder',
    '''
## Stack (combine)
- Drop a document onto another and its pages are appended to it at once
- Keep stacking onto the combined document as often as you like
- `Undo` at the bottom reverts the last stack
- Hold `Shift` while dropping to just lay it on top
- Select several and press `Stack` to combine them in selection order

## Spread
- Splits a multi-page document into one sheet per page, laid side by side
- Stack the sheets again to put them back together
- `Split (keep original)` makes one document per page and keeps the original

## Binders
- Bind documents together while keeping each one (shown as tabs in the viewer)
- Drop documents onto a binder to add them; `Unbind` takes them apart
''',
  ),
  (
    'This PC and folders',
    '''
## Desk folders (top left)
- Click a folder to open its desk
- Drop desk documents onto a folder to move them there
- Right-click: new folder, rename, delete

## This PC (bottom left)
- Browse Desktop, Documents, Downloads and drives such as C: and D:
- Drag a PDF or image from the disk onto the desk to move it in (`Ctrl`: copy)
- Drag desk documents onto a disk folder to copy them out; annotations are burned in and a binder becomes one PDF
- Drag a file onto another disk folder to move it (`Ctrl`: copy)
- Right-click a folder → `Open as desk` to work on that folder directly
- Drag the `This PC` header up or down to share the height
''',
  ),
  (
    'Viewer and annotations',
    '''
Double-click a document to open the viewer. Annotations are kept apart from the PDF, which stays unchanged.

## Drawing tools
- Pen, highlighter, line, arrow, rectangle, ellipse, text, sticky note, date stamp, eraser
- `Shift`+drag: 45° lines, squares, circles
- The select tool moves, the corner handle resizes, double-click edits text

## Properties
Select an annotation, right-click → `Properties…`
- Line color, width, style (solid, dashed, dotted, dash-dot), arrow heads
- Background color and opacity (shapes can have a background and no line)
- Font, size, bold, italic, text color
- 🎨: a 126-color palette, recent colors, or a `#RRGGBB` code

## Pages
In the page list on the left: drag to reorder, rotate, delete, extract, insert files

## Search and view
`Ctrl+F` search, `F3` next, `Ctrl+wheel` zoom, `Ctrl+0` fit width
''',
  ),
  (
    'Copying a region',
    '''
Cut out part of a page and paste it into another document.

## How
- Pick `Copy region` (the scissors) on the viewer toolbar
- Drag a box around the part to copy
- Open another document (or page) and press `Ctrl+V`, or right-click → `Paste`
- The pasted picture moves and resizes like any annotation

## Good to know
- Annotations inside the box are part of the picture
- The text inside the box also goes to the Windows clipboard, for Notepad, Word and so on
- Exporting or printing keeps the pasted picture in the PDF
''',
  ),
  (
    'Printing and the PDF Desk printer',
    '''
## The PDF Desk printer
Print from any program (Word, Excel, a browser…) and the document lands on the desk, with no save dialog.
- Choose `Install` on the notice at first start, or `File` → `'PDF Desk' printer setup…`
- Confirm the administrator prompt (UAC); it becomes the default printer
- No driver is installed: it uses Windows' own "Microsoft Print to PDF"
- Choosing the plain "Microsoft Print to PDF" asks where to save and does not reach the desk

## Export and print
- `Export PDF`: a PDF with the annotations burned in, which looks the same in any viewer
- `Print` (`Ctrl+P`): prints with the annotations
''',
  ),
  (
    'Trash and undo',
    '''
## Trash
- Deleted documents go to the trash first (kept 30 days)
- `Undo` right after deleting brings them back
- `File` → `Trash…` to `Restore`, `Delete permanently` or `Empty trash`

## Undo
- Stacking: `Undo` at the bottom
- Annotations in the viewer: `Ctrl+Z` undo, `Ctrl+Y` redo
- Changes made in the properties dialog undo in one `Ctrl+Z`
''',
  ),
  (
    'Themes and languages',
    '''
## Themes
Pick one with 🎨 at the top right: iOS Light, iOS Dark, Classic (DocuWorks), Paper (sepia), Forest, Midnight

## Languages
Pick one with 🌐 at the top right: 한국어, 日本語, 中文, English, Español, Français

Both are remembered for next time.
''',
  ),
  (
    'Keyboard shortcuts',
    '''
## Desk
- `Ctrl+N` new document, `Ctrl+O` import, `Ctrl+P` print
- `Ctrl+A` select all, `Ctrl+D` duplicate, `F2` rename, `Del` delete
- `Ctrl+F` search names, `F5` refresh, `F1` manual
- `Ctrl`+wheel zoom, `Ctrl`+drag copy, `Shift`+drop lay on top without stacking
- Preview: `←` `→` `PageUp` `PageDown`

## Viewer
- `Ctrl+Z` / `Ctrl+Y` undo / redo
- `Ctrl+C` / `Ctrl+V` copy / paste annotations and regions
- `Ctrl+F` search, `F3` / `Shift+F3` next / previous
- `Ctrl+wheel`, `Ctrl +`, `Ctrl -` zoom, `Ctrl+0` fit width
- `Esc` select tool, `Del` delete the selected annotations
''',
  ),
  (
    'Troubleshooting',
    '''
## "The file is in use and couldn't be processed"
- If the desk folder is inside OneDrive, files are locked while they sync
- When `Move the desk folder` appears at start, choose `Move` (to C:\\Users\\<name>\\PdfDesk)
- Close the document if another PDF viewer has it open, then try again

## Printing doesn't reach the desk
- Check that the printer in the print dialog is `PDF Desk`
- PDF Desk must be running to put the document on the desk

## A font looks different
- A font must be installed on the PC to go into the PDF; otherwise Malgun Gothic is used
''',
  ),
];
