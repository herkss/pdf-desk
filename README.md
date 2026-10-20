# PDF Desk

DocuWorks 스타일의 문서 관리/편집 프로그램입니다. Flutter로 만든 **Windows 64비트(x64, ARM64)** 데스크톱 앱이며, 문서 형식으로 표준 PDF를 사용합니다.

## 주요 기능

### 데스크 (DocuWorks Desk 대응)
| 기능 | 조작 |
|---|---|
| 문서를 썸네일로 자유 배치 | 끌어서 이동. 위치는 폴더별로 저장됨 |
| 가져오기 | 탐색기에서 PDF·이미지(jpg/png/bmp/gif/webp/tif)를 끌어다 놓기, 또는 `Ctrl+O`. 이미지는 PDF로 변환됨 |
| 다중 선택 | `Ctrl`/`Shift`+클릭, 빈 곳을 드래그해 범위 선택, `Ctrl+A` |
| 묶기 | 여러 문서를 하나의 문서로 합치기. 문서를 다른 문서 위에 놓아도 됨 |
| 분할 | 페이지마다 별도 문서로 나누기 |
| 바인더 | 여러 문서를 바인더로 묶고(뷰어에서 탭으로 표시), 해제. 바인더 위에 문서를 놓으면 추가됨 |
| 폴더 | 왼쪽 트리에서 폴더 만들기/이름 변경/삭제. 문서를 폴더로 끌어다 놓으면 이동 |
| 기타 | 회전, 이름 바꾸기(`F2`), 복제(`Ctrl+D`), 삭제(`Del`), 정렬(이름순/수정일순), 이름 검색, 썸네일 크기(`Ctrl+휠`) |
| 출력 | PDF 내보내기(주석 포함), 인쇄(`Ctrl+P`) |

### 뷰어 (DocuWorks Viewer 대응)
- **주석**: 펜, 형광펜, 직선, 화살표, 사각형, 타원, 텍스트, 부전(스티커 메모), 날짜 도장, 지우개
  - 선택 도구로 이동, 모서리 핸들로 크기 조절, 더블클릭으로 텍스트 편집
  - `Shift`+드래그: 45° 단위 직선, 정사각형, 정원
  - 색상·굵기·글자 크기 변경, 복사/붙여넣기, 맨 앞/뒤로, 주석 표시/숨기기
  - 실행 취소/다시 실행 (`Ctrl+Z`, `Ctrl+Y`), 자동 저장
- **페이지 편집**(왼쪽 페이지 목록): 드래그로 순서 변경, 회전, 삭제, 추출(새 문서로), 앞/뒤에 파일 삽입
- 문서 안 텍스트 검색(`Ctrl+F`, `F3`), 확대/축소(`Ctrl+휠`, `Ctrl +/-`), 폭 맞춤(`Ctrl+0`), 전체 페이지 보기
- 바인더를 열면 문서마다 탭이 생김. 탭을 우클릭해 순서 변경, 이름 변경, 바인더에서 꺼내기

### 주석 저장 방식
DocuWorks처럼 **주석은 원본과 분리된 레이어**로 보관되므로 원본 PDF가 바뀌지 않습니다. 언제든 수정하거나 지울 수 있습니다.
"PDF 내보내기"나 "인쇄"를 하면 주석이 PDF 안에 실제 벡터/텍스트로 새겨지며(한글 폰트 포함), 어떤 PDF 뷰어에서도 똑같이 보입니다.

```text
데스크폴더/
  견적서.pdf
  2026 보고서.pdbinder/         ← 바인더 (폴더)
    1월.pdf
    binder.json                ← 문서 순서
  .pdfdesk/
    layout.json                ← 데스크 위 문서 위치
    annotations/견적서.pdf.json ← 주석
```

기본 데스크 폴더는 `문서\PdfDesk`이며, 환경 설정(톱니바퀴)에서 바꿀 수 있습니다. 도장의 문구와 이름도 환경 설정에서 정합니다.

## Windows에서 빌드하기

준비물:
1. [Flutter SDK](https://docs.flutter.dev/get-started/install/windows) 3.44 이상
2. Visual Studio 2022의 **"C++를 사용한 데스크톱 개발"** 워크로드

```powershell
flutter pub get
flutter run -d windows             # 개발 실행
flutter build windows --release    # 배포용 빌드
```

결과물은 `build\windows\x64\runner\Release\`에 생깁니다. 이 폴더 전체(`pdf_desk.exe`, `pdfium.dll`, `msvcp140.dll`, `vcruntime140*.dll`, `data\` 등)를 복사하면 다른 PC에서도 실행됩니다. Visual C++ 런타임 DLL이 함께 들어가므로 대상 PC에 재배포 패키지를 설치할 필요가 없습니다.
ARM64 PC에서 빌드하면 ARM64용이 만들어집니다.

GitHub에 올리면 `.github/workflows/build-windows.yml`이 자동으로 x64 빌드를 만듭니다.

## 테스트

```powershell
flutter test
```

- `test/pdf_ops_test.dart`: 묶기, 분할, 회전, 순서 변경, 삭제 시 주석 위치 유지, 주석 새기기(회전된 페이지 포함), 이미지 가져오기, 바인더
- `test/ui_smoke_test.dart`: 데스크 표시, 선택, 뷰어 열기, 펜으로 그리기, 자동 저장
- 한글 새기기 테스트는 Windows에서 맑은 고딕을 자동으로 사용합니다. 다른 OS에서는 `PDFDESK_FONT=한글.ttf`를 지정하세요.

## 구조

```text
lib/
  models/annotation.dart          주석 모델 (JSON, 충돌 판정, 회전)
  services/
    pdf_ops.dart                  묶기/분할/페이지 편집/가져오기/바인더 (pdfrx = PDFium)
    flatten.dart                  주석을 PDF에 새기기 (PDFium FFI)
    storage.dart                  주석/배치/바인더 파일 저장
    thumbnails.dart               썸네일 캐시 (동시 렌더링 제한)
    desk_controller.dart          데스크 상태, 폴더 감시
  ui/desk/                        데스크 화면, 폴더 트리, 캔버스
  ui/viewer/                      뷰어, 페이지 목록, 주석 입력 레이어
```

## 아직 없는 기능
- DocuWorks 고유 형식(.xdw/.xbd) 읽기·쓰기 (형식이 공개되어 있지 않음)
- OCR, 스캐너 연동, "DocuWorks Printer" 같은 가상 프린터
- 전자 서명, 문서 암호 설정
- 여러 뷰어 창 동시 열기 (현재는 데스크 → 뷰어 화면 전환)
