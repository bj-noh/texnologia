# Subagent 9: QA and Test Agent - PaperForge 테스트 전략

## 목표

PaperForge의 QA 전략은 LaTeX 작성 앱의 핵심 루프인 "프로젝트 열기 -> 편집 -> 빌드 -> 오류 이해 -> PDF 확인 -> 소스/PDF 이동"을 안정적으로 검증하는 데 집중한다. 테스트는 단순한 화면 동작 확인이 아니라 실제 LaTeX 프로젝트, TeX 엔진, bibliography 도구, macOS 파일 권한, Apple Silicon/Intel 환경 차이를 포함해야 한다.

MVP 기준으로는 대표 fixture 프로젝트에서 빌드와 오류 패널이 신뢰 가능하게 동작하는지 확인하고, Beta/v1.0으로 갈수록 SyncTeX, bibliography, 대형 프로젝트, Quick Fix, 제출 준비 흐름까지 회귀 테스트 범위를 넓힌다.

## 테스트 원칙

- 도메인 로직은 unit test로 빠르게 검증한다.
- 외부 프로세스, 파일 시스템, TeX toolchain은 integration test에서 실제 명령 또는 통제된 fake runner로 검증한다.
- SwiftUI/AppKit/PDFKit 상호작용은 UI test와 수동 탐색 테스트를 병행한다.
- LaTeX 로그 파싱은 fixture 기반 golden test로 회귀를 막는다.
- macOS sandbox, security-scoped bookmark, iCloud Drive 경로, 공백/한글 경로는 별도 호환성 축으로 관리한다.
- 테스트 실패는 사용자가 실제로 겪는 문제 단위로 기록한다. 예: "Biber 실패 메시지가 citation issue로 표시되지 않음", "PDF reload 후 페이지 위치가 1쪽으로 초기화됨".

## 테스트 피라미드

```text
Manual Exploratory / Release Smoke
  - 신규 사용자 흐름, 다양한 TeX 설치 상태, 실제 논문 프로젝트

UI Tests
  - 프로젝트 열기, 편집, 빌드 버튼, 오류 클릭, PDF reload, 설정 변경

Integration Tests
  - latexmk/engines/BibTeX/Biber/process/file watcher/PDF artifact

Unit Tests
  - tokenizer, indexer, command generation, log parser, issue model, settings
```

권장 비율:

| 레이어 | 비중 | 실행 시점 | 목적 |
| --- | ---: | --- | --- |
| Unit | 55% | 모든 PR, pre-commit 가능 | 빠른 회귀 감지 |
| Integration | 30% | 모든 PR 또는 nightly matrix | 실제 파일/프로세스 경계 검증 |
| UI | 10% | 주요 PR, nightly, release candidate | 사용자 워크플로우 검증 |
| Manual/Exploratory | 5% | milestone/release 전 | 설치/환경/감성 품질 확인 |

## 테스트 환경 매트릭스

### macOS

| 축 | 최소 | 권장 | 릴리스 전 필수 |
| --- | --- | --- | --- |
| macOS 버전 | macOS 13 Ventura | macOS 14 Sonoma, macOS 15 Sequoia | 지원 범위 전체 smoke |
| CPU | Intel x86_64 | Apple Silicon arm64 | 둘 다 |
| Rosetta | 선택 | Apple Silicon에서 Intel TeX binary 실행 시나리오 | smoke |
| 파일 시스템 | 로컬 APFS | iCloud Drive, 공백/한글 경로 | 필수 |
| sandbox | 개발 빌드 | App Sandbox enabled 빌드 | App Store 후보 필수 |

### TeX Toolchain

| 도구 | 검증 내용 |
| --- | --- |
| MacTeX/TeX Live | `/Library/TeX/texbin` 감지, PATH 없이 실행 가능 여부 |
| BasicTeX | 누락 패키지 오류 표시, 설치 안내 UX |
| `latexmk` | 기본 빌드, 엔진 플래그, clean/rebuild, aux/outdir 처리 |
| `pdflatex` | 직접 fallback 빌드, cross-reference rerun |
| `xelatex` | UTF-8/한글/fontspec 프로젝트 빌드 |
| `lualatex` | LuaLaTeX 전용 package와 font 처리 |
| `bibtex` | classic BibTeX bibliography workflow |
| `biber` | BibLaTeX workflow, bcf 생성/실패 처리 |
| `makeindex` | v1.0 이후 index 프로젝트 회귀 |

## 테스트 대상 기능

| 기능 | Unit | Integration | UI | 수동 |
| --- | --- | --- | --- | --- |
| 프로젝트 열기/권한 | bookmark model | sandbox 경로 접근 | open panel flow | iCloud/외장 드라이브 |
| 인덱싱 | parser/graph | multi-file fixture | sidebar outline | 대형 프로젝트 |
| 편집기 | tokenizer/highlight range | file save/load | typing/autocomplete | IME/한글 입력 |
| 빌드 시스템 | command/log parser | TeX 엔진 실행 | build button/status | toolchain 누락 |
| 오류 패널 | issue grouping | invalid fixture logs | issue click jump | 초보자 이해성 |
| PDF viewer | state model | artifact reload | page/zoom/search | 다크 모드/큰 PDF |
| SyncTeX | path/coordinate parser | synctex command | forward/inverse search | 복잡한 include |
| bibliography | bib parser | BibTeX/Biber 빌드 | citation autocomplete | 깨진 `.bib` |
| 설정 | Codable/defaults | persisted recipes | preferences UI | 앱 재시작 |

## Sample Fixture Projects

fixture는 `Tests/Fixtures/LaTeXProjects/` 아래에 둔다. 각 fixture는 `manifest.json`을 포함해 root file, 예상 엔진, 예상 성공 여부, 예상 issue, 기대 산출물을 선언한다.

```text
Tests/Fixtures/LaTeXProjects/
  001-basic-article/
  002-multifile-input-include/
  003-bibtex-classic/
  004-biber-biblatex/
  005-xelatex-unicode-fonts/
  006-lualatex-modern/
  007-invalid-syntax/
  008-missing-file-and-image/
  009-crossref-rerun/
  010-synctex-navigation/
  011-large-thesis/
  012-path-edge-cases/
```

### 001-basic-article

목적: 설치 직후 기본 빌드 smoke.

```text
main.tex
figures/
manifest.json
```

기대:

- `latexmk -pdf` 성공
- `main.pdf`, `main.log`, `main.synctex.gz` 생성
- 오류 0개, 경고 0개 또는 허용 경고만 표시
- PDF viewer가 1쪽 문서를 로드

### 002-multifile-input-include

목적: `\input`, `\include`, nested directory, relative path indexing 검증.

```text
main.tex
sections/introduction.tex
sections/method.tex
sections/results.tex
appendix/proofs.tex
manifest.json
```

기대:

- file graph edge가 `main.tex -> sections/*.tex`, `main.tex -> appendix/proofs.tex`로 생성
- section outline이 파일 순서대로 정렬
- included file 저장 시 root 재빌드 트리거
- 오류가 included file line으로 매핑

### 003-bibtex-classic

목적: `\bibliography{refs}`와 BibTeX workflow 검증.

```text
main.tex
refs.bib
manifest.json
```

기대:

- `latexmk`는 BibTeX pass를 자동 수행
- 직접 fallback 모드에서는 bibliography 필요 issue 또는 explicit BibTeX pass가 실행
- citation key 자동완성 후보에 `knuth1984`, `lamport1994` 표시
- 누락 citation은 warning issue로 표시

### 004-biber-biblatex

목적: BibLaTeX/Biber workflow 검증.

```text
main.tex
library.bib
manifest.json
```

기대:

- `\addbibresource{library.bib}` 인덱싱
- `latexmk -pdf` 또는 `latexmk -pdf -use-biber` 구성에서 성공
- Biber 미설치 시 "biber 실행 파일을 찾을 수 없음"으로 분류
- `.bcf` 생성 후 biber 실패 로그가 bibliography issue로 표시

### 005-xelatex-unicode-fonts

목적: XeLaTeX, UTF-8, 한글/수식/폰트 처리.

```text
main.tex
chapters/한글-섹션.tex
manifest.json
```

기대:

- `xelatex` 또는 `latexmk -xelatex`로 성공
- 한글 파일명과 한글 section title이 인덱싱됨
- 공백/한글 경로에서도 process argument escaping 문제가 없음

### 006-lualatex-modern

목적: LuaLaTeX 엔진과 LuaLaTeX 전용 로그 차이 검증.

기대:

- `lualatex` 또는 `latexmk -lualatex` 성공
- font/cache 관련 warning을 fatal error로 오분류하지 않음
- SyncTeX 산출물이 있으면 PDF navigation 후보 생성

### 007-invalid-syntax

목적: 흔한 LaTeX 오류 파싱 회귀.

포함 오류:

- 닫히지 않은 brace
- `\begin{figure}`와 `\end{table}` mismatch
- undefined control sequence
- missing `$`
- runaway argument
- duplicated label
- undefined reference

기대:

- fatal error는 첫 원인 위치 중심으로 group
- issue list에 file, line, severity, raw log excerpt가 표시
- 오류 클릭 시 해당 source line으로 이동
- 빌드 실패 후 이전 PDF가 있으면 viewer는 이전 PDF와 실패 상태를 명확히 표시

### 008-missing-file-and-image

목적: 누락된 `\input`, image, `.bib`, `.sty` 처리.

기대:

- 인덱서가 missing file diagnostic 생성
- 빌드 로그의 `File 'x' not found`를 missing resource issue로 분류
- 사용자가 프로젝트 사이드바에서 누락 파일을 식별 가능

### 009-crossref-rerun

목적: direct engine fallback의 pass 반복 정책 검증.

기대:

- 첫 pass에서 `Label(s) may have changed` 감지
- 최대 pass 수 내에서 재실행
- 안정화 후 PDF 성공 처리
- pass limit 초과 시 non-fatal rerun warning 표시

### 010-synctex-navigation

목적: source-to-PDF, PDF-to-source 좌표 회귀.

기대:

- `-synctex=1` 활성화 시 `.synctex.gz` 생성
- source line에서 PDF page/destination 후보 생성
- included file 위치도 root 기준으로 resolve
- 경로에 공백이 있어도 `synctex` command argument가 깨지지 않음

### 011-large-thesis

목적: 성능과 장시간 안정성.

규모:

- `.tex` 40개 이상
- `.bib` entry 500개 이상
- figure placeholder 100개 이상
- PDF 100쪽 이상

기대:

- 초기 인덱싱 목표 시간: 5초 이내
- 저장 후 증분 인덱싱: 500ms 이내 목표
- 저장 후 PDF 갱신: 중형 프로젝트 기준 2초 목표, 대형은 별도 baseline 기록
- UI typing latency가 체감될 정도로 증가하지 않음

### 012-path-edge-cases

목적: macOS 경로/권한 edge case.

경로 예:

```text
PaperForge Fixtures/space path/main.tex
한글 프로젝트/main.tex
iCloud Drive/PaperForge Test/main.tex
symlinked-root/main.tex
```

기대:

- URL/path 변환에서 percent encoding 문제가 없음
- Process argument가 shell string이 아니라 array로 전달됨
- security scoped access가 앱 재시작 후에도 복원됨

## Fixture Manifest 예시

```json
{
  "id": "004-biber-biblatex",
  "rootFile": "main.tex",
  "preferredEngine": "pdflatex",
  "buildTool": "latexmk",
  "bibliographyTool": "biber",
  "expected": {
    "buildSucceeds": true,
    "pdf": "main.pdf",
    "synctex": true,
    "issues": []
  },
  "tags": ["bibliography", "biber", "biblatex", "regression"]
}
```

## Unit Test Cases

### Build Command Generation

| ID | Given | When | Then |
| --- | --- | --- | --- |
| U-BLD-001 | default config + latexmk path | command 생성 | `latexmk`, `-pdf`, `-file-line-error`, `-synctex=1`, `-no-shell-escape` 포함 |
| U-BLD-002 | preferredEngine `xeLaTeX` | latexmk command 생성 | `-xelatex` 포함 |
| U-BLD-003 | preferredEngine `luaLaTeX` | latexmk command 생성 | `-lualatex` 포함 |
| U-BLD-004 | latexmk 없음 | command 생성 | direct engine fallback command 생성 |
| U-BLD-005 | shellEscape disabled | command 생성 | `-no-shell-escape` 포함 |
| U-BLD-006 | shellEscape enabled | command 생성 | `-shell-escape` 포함, UI risk flag 연결 |
| U-BLD-007 | 경로에 공백/한글 | command 생성 | argument array가 path를 보존 |
| U-BLD-008 | engine path 없음 | command 생성 | missing executable error |

### Log Parser

| ID | 로그 입력 | 기대 issue |
| --- | --- | --- |
| U-LOG-001 | `! Undefined control sequence.` | error, command 위치 |
| U-LOG-002 | `LaTeX Error: File 'foo.sty' not found.` | missing package/file |
| U-LOG-003 | `Runaway argument?` | runaway argument |
| U-LOG-004 | `Missing $ inserted.` | math delimiter error |
| U-LOG-005 | `Label(s) may have changed.` | rerun required warning |
| U-LOG-006 | `Citation 'x' undefined` | citation warning |
| U-LOG-007 | `Package biblatex Warning` | bibliography warning |
| U-LOG-008 | Biber `ERROR - Cannot find 'refs.bib'` | missing bibliography resource |
| U-LOG-009 | `Overfull \hbox` | layout diagnostic, not fatal |
| U-LOG-010 | multi-line nested error | 하나의 issue group |

### Project Indexer

| ID | 입력 | 기대 |
| --- | --- | --- |
| U-IDX-001 | `\input{intro}` | `intro.tex` edge |
| U-IDX-002 | `\include{chapters/a}` | include edge |
| U-IDX-003 | `\addbibresource{refs.bib}` | bib resource edge |
| U-IDX-004 | `\bibliography{a,b}` | `a.bib`, `b.bib` edge |
| U-IDX-005 | nested labels | label definitions 추출 |
| U-IDX-006 | `\citep{a,b}` | citation uses 2개 |
| U-IDX-007 | comment 안의 `\input{x}` | dependency로 추출하지 않음 |
| U-IDX-008 | missing included file | missing file diagnostic |

### Editor Core

| ID | 검증 |
| --- | --- |
| U-EDT-001 | `%` 이후 line comment token |
| U-EDT-002 | escaped percent `\%`는 comment가 아님 |
| U-EDT-003 | `\begin{equation}` token sequence |
| U-EDT-004 | `$`, `$$`, `\(`, `\[` math delimiter |
| U-EDT-005 | incremental highlight range가 변경 paragraph로 제한 |
| U-EDT-006 | autocomplete context가 `\cite{`에서 citation provider 선택 |
| U-EDT-007 | bracket matcher가 nested brace 쌍을 선택 |

### PDF Viewer / Sync Model

| ID | 검증 |
| --- | --- |
| U-PDF-001 | reload 전후 pageIndex 유지 |
| U-PDF-002 | reload 전후 scaleFactor 유지 |
| U-PDF-003 | page count 변경 시 pageIndex clamp |
| U-PDF-004 | normalized visible rect 복원 |
| U-PDF-005 | missing PDF artifact는 empty/error state |
| U-SYN-001 | SyncTeX output path parser |
| U-SYN-002 | included file path normalization |
| U-SYN-003 | PDF coordinate -> source location 변환 실패 시 graceful nil |

### Persistence / Settings

| ID | 검증 |
| --- | --- |
| U-SET-001 | build profile Codable round trip |
| U-SET-002 | recent project store deduplication |
| U-SET-003 | security bookmark stale 상태 표시 |
| U-SET-004 | toolchain path override persistence |
| U-SET-005 | window/editor/PDF state restore |

## Integration Test Cases

Integration test는 두 계층으로 나눈다.

- hermetic: fake `ProcessRunner`, fixture log, temporary directory 사용
- toolchain: 실제 MacTeX/TeX Live 실행. CI에서 optional 또는 nightly로 운영

| ID | Fixture | 환경 | 절차 | 기대 |
| --- | --- | --- | --- | --- |
| I-BLD-001 | 001-basic-article | latexmk | open -> build | PDF/log/synctex 생성, success status |
| I-BLD-002 | 001-basic-article | no latexmk + pdflatex | direct fallback | PDF 생성, pass count 기록 |
| I-BLD-003 | 005-xelatex-unicode-fonts | xelatex | build | UTF-8 source 성공 |
| I-BLD-004 | 006-lualatex-modern | lualatex | build | LuaLaTeX 로그 정상 분류 |
| I-BIB-001 | 003-bibtex-classic | latexmk | build | BibTeX pass 포함, citation resolved |
| I-BIB-002 | 004-biber-biblatex | latexmk+biber | build | Biber pass 포함, bibliography 출력 |
| I-BIB-003 | 004-biber-biblatex | biber missing | build | missing executable issue |
| I-MUL-001 | 002-multifile-input-include | any | included file 수정 | root 재빌드 트리거 |
| I-MUL-002 | 002-multifile-input-include | any | included file syntax error | issue location이 included file |
| I-ERR-001 | 007-invalid-syntax | latexmk | build | build failed, expected issue set |
| I-ERR-002 | 008-missing-file-and-image | latexmk | build | missing resource issues |
| I-RER-001 | 009-crossref-rerun | direct pdflatex | build | rerun 감지 후 성공 |
| I-SYN-001 | 010-synctex-navigation | synctex | source line query | PDF destination 반환 |
| I-SYN-002 | 010-synctex-navigation | synctex | PDF position query | source file/line 반환 |
| I-PTH-001 | 012-path-edge-cases | path with spaces | build | argument escaping 문제 없음 |
| I-PTH-002 | 012-path-edge-cases | Korean path | build/index | URL normalization 정상 |
| I-SBX-001 | any | sandbox enabled | reopen project | bookmark access 복원 |
| I-PER-001 | 011-large-thesis | release build | index/build | baseline 안의 시간 기록 |

## UI Test Scenarios

UI test는 XCTest UI test를 기본으로 하되, PDFKit 내부 렌더링과 AppKit selection은 필요한 경우 accessibility identifier와 view model hook으로 보강한다.

### UI-001: 첫 프로젝트 열기와 빌드

1. 앱 실행
2. `Open Project` 선택
3. `001-basic-article` 폴더 선택
4. main file 자동 감지 확인
5. Build 버튼 클릭
6. 빌드 상태가 running -> success로 변함
7. PDF pane에 1쪽 문서 표시

### UI-002: 저장 후 자동 빌드와 PDF reload

1. `001-basic-article` 열기
2. editor에 문장 추가
3. 저장
4. 자동 빌드 indicator 표시
5. PDF reload 후 기존 zoom/page 유지

### UI-003: 오류 패널에서 소스 이동

1. `007-invalid-syntax` 열기
2. Build 실행
3. Issue Navigator가 열리고 error count 표시
4. 첫 오류 클릭
5. editor caret이 expected file/line으로 이동
6. raw log disclosure를 열면 원문 로그 일부 표시

### UI-004: Multi-file sidebar와 outline

1. `002-multifile-input-include` 열기
2. sidebar에 included files 표시
3. outline에서 `Methods` 클릭
4. editor가 `sections/method.tex` 해당 위치로 이동
5. 해당 파일 수정 후 저장하면 root build가 실행

### UI-005: Citation autocomplete

1. `003-bibtex-classic` 열기
2. editor에서 `\cite{` 입력
3. citation popup 표시
4. 후보 검색/선택
5. key가 삽입되고 brace가 유지

### UI-006: Build profile 변경

1. `005-xelatex-unicode-fonts` 열기
2. build settings에서 XeLaTeX 선택
3. 저장 후 Build
4. status detail에 `xelatex` 또는 `latexmk -xelatex` 표시
5. 앱 재시작 후 설정 유지

### UI-007: PDF viewer 기본 조작

1. 성공 fixture 열기
2. zoom in/out 실행
3. page navigation 실행
4. PDF search 실행
5. rebuild 후 page/zoom이 유지되는지 확인

### UI-008: SyncTeX forward/inverse search

1. `010-synctex-navigation` 열기
2. source line에서 forward search 실행
3. PDF viewer가 expected page로 이동
4. PDF 위치에서 inverse search 실행
5. editor가 expected source line으로 이동

### UI-009: Toolchain missing UX

1. test environment에서 TeX PATH를 비움
2. Build 클릭
3. Preferences 또는 안내 UI로 이동 가능한 error 표시
4. 앱이 crash 없이 idle 상태로 복귀

### UI-010: macOS appearance와 accessibility

1. Light/Dark mode 각각 실행
2. editor, issue navigator, PDF chrome contrast 확인
3. VoiceOver label이 핵심 버튼에 존재
4. keyboard-only로 open/build/issues/PDF pane 이동 가능

## Invalid LaTeX Error Regression Set

오류 회귀 세트는 로그 parser의 golden output과 UI 표시를 모두 검증한다.

| 오류 | 예시 | 기대 분류 |
| --- | --- | --- |
| Undefined control sequence | `\unknwoncommand` | fatal compile error |
| Missing package | `\usepackage{not-installed}` | missing package |
| Missing input file | `\input{missing}` | missing source file |
| Missing image | `\includegraphics{missing.png}` | missing asset |
| Environment mismatch | `\begin{figure}...\end{table}` | environment mismatch |
| Unclosed brace | `\textbf{abc` | syntax/bracing |
| Math mode error | `x_1` outside math | math mode |
| Missing `$` | `$x+y` | math delimiter |
| Duplicate label | two `\label{sec:intro}` | duplicate label warning |
| Undefined reference | `\ref{missing}` | unresolved reference warning |
| Undefined citation | `\cite{missing}` | unresolved citation warning |
| BibTeX malformed entry | missing comma/brace | bibliography parse/build error |
| Biber data model error | invalid field/data | bibliography issue |
| Overfull hbox | long unbreakable line | layout diagnostic |

## CI와 실행 전략

### PR 기본

- Swift unit tests
- hermetic integration tests with fake process runner
- fixture manifest validation
- log parser golden tests
- lint 또는 formatting check

### Nightly

- 실제 TeX Live/MacTeX toolchain integration
- `pdflatex`, `xelatex`, `lualatex` matrix
- BibTeX/Biber matrix
- large thesis performance baseline
- macOS latest stable + previous supported version

### Release Candidate

- Apple Silicon native smoke
- Intel native smoke
- App Sandbox enabled build
- signed/notarized app launch smoke
- iCloud Drive project open/build smoke
- clean machine with no TeX 설치 상태 smoke
- BasicTeX only 상태 smoke
- MacTeX full 상태 smoke

## 테스트 데이터 관리

- fixture 프로젝트는 작고 결정적이어야 한다.
- 외부 네트워크 다운로드가 필요한 package에 의존하지 않는다.
- PDF golden binary 비교는 피하고, page count/text extraction/artifact existence 중심으로 검증한다.
- `.log` golden fixture는 엔진/TeX Live 버전 차이를 고려해 stable substring과 normalized parser output을 비교한다.
- 성능 fixture는 용량이 클 수 있으므로 별도 LFS 또는 generated fixture 전략을 검토한다.
- license가 불명확한 실제 논문 프로젝트는 저장소에 넣지 않고 private QA corpus로 관리한다.

## macOS 호환성 체크포인트

### 파일 접근

- open panel로 선택한 프로젝트에 security scoped bookmark 생성
- 앱 재시작 후 bookmark resolve
- stale bookmark 갱신
- sandbox 환경에서 aux/output directory 생성
- read-only 프로젝트에서 오류 메시지 표시

### Process 실행

- shell을 거치지 않고 executable URL + argument array 사용
- `/Library/TeX/texbin`, `/usr/local/texlive/*/bin/*`, user override path 탐색
- environment `PATH`가 비어 있어도 configured path 사용
- process cancel 시 child process 정리
- stdout/stderr가 큰 로그에서도 deadlock 없음

### Apple Silicon / Intel

- arm64 앱에서 arm64 TeX binary 실행
- Intel 앱 또는 Rosetta 환경에서 TeX binary 실행
- universal binary packaging 확인
- architecture mismatch 오류를 사용자가 이해 가능한 toolchain issue로 표시

### AppKit/PDFKit

- macOS 버전별 PDFKit reload 차이 확인
- Retina/non-Retina display에서 PDF rendering 확인
- 다크 모드 background/selection contrast 확인
- IME 조합 중 syntax highlighting이 입력을 깨지 않음

## 성능 기준

| 항목 | MVP 목표 | 측정 방식 |
| --- | ---: | --- |
| 기본 프로젝트 cold open | 1초 이내 | app signpost |
| 중형 프로젝트 초기 인덱싱 | 3초 이내 | fixture timing |
| 대형 프로젝트 초기 인덱싱 | 5초 이내 목표 | performance test |
| 저장 후 증분 인덱싱 | 500ms 이내 | changed file only |
| 저장 후 PDF 갱신 | 2초 이내 목표 | build start -> PDF visible |
| editor typing latency | 16ms frame budget 목표 | UI responsiveness |
| log parser | 100KB log 100ms 이내 | unit performance |

성능 테스트는 절대값만 보지 않고 baseline 대비 regression도 기록한다. CI machine 성능 차이를 고려해 release 판단에는 로컬 기준 장비와 nightly trend를 함께 사용한다.

## 결함 분류

| Priority | 기준 | 예 |
| --- | --- | --- |
| P0 | 데이터 손실, crash, 기본 빌드 불가 | 저장 시 파일 손상, PDFKit crash |
| P1 | 핵심 워크플로우 차단 | 정상 프로젝트가 빌드 실패로 표시 |
| P2 | 우회 가능한 주요 기능 오류 | citation autocomplete 누락 |
| P3 | 시각적/문구/저위험 오류 | alignment, copy issue |

릴리스 차단 기준:

- P0 미해결 0개
- MVP 핵심 워크플로우의 P1 미해결 0개
- known issue로 문서화되지 않은 toolchain 호환성 실패 0개
- sample fixture success set 100% 통과

## Release Checklist

### 기능 회귀

- [ ] `001-basic-article` 빌드 성공
- [ ] `002-multifile-input-include` 인덱싱/빌드 성공
- [ ] `003-bibtex-classic` BibTeX workflow 성공
- [ ] `004-biber-biblatex` Biber workflow 성공 또는 미설치 UX 확인
- [ ] `005-xelatex-unicode-fonts` XeLaTeX 성공
- [ ] `006-lualatex-modern` LuaLaTeX 성공
- [ ] `007-invalid-syntax` expected issue 표시
- [ ] `008-missing-file-and-image` missing resource issue 표시
- [ ] `009-crossref-rerun` direct fallback rerun 동작
- [ ] `010-synctex-navigation` forward search smoke

### macOS/배포

- [ ] Apple Silicon native 실행
- [ ] Intel native 실행
- [ ] universal app packaging 확인
- [ ] signed build 실행
- [ ] notarization 통과
- [ ] sandbox enabled smoke
- [ ] iCloud Drive 프로젝트 open/build
- [ ] 공백/한글 경로 프로젝트 open/build
- [ ] TeX 미설치 상태 error UX
- [ ] BasicTeX 상태 missing package UX
- [ ] MacTeX full 상태 success path

### UI/UX

- [ ] Light mode smoke
- [ ] Dark mode smoke
- [ ] keyboard-only open/build/error navigation
- [ ] issue click source jump
- [ ] PDF reload 후 page/zoom 유지
- [ ] Preferences build profile 저장/복원
- [ ] 앱 재시작 후 recent project/build settings 복원
- [ ] VoiceOver 핵심 control label 확인

### 안정성

- [ ] build cancel 후 orphan process 없음
- [ ] 긴 로그 출력에서 UI freeze 없음
- [ ] PDF 교체 중 crash 없음
- [ ] read-only project에서 명확한 오류
- [ ] large thesis fixture performance baseline 기록
- [ ] crash log 또는 unified logging에 release blocker 없음

## 권장 자동화 구조

```text
PaperForgeTests/
  Unit/
    BuildCommandGeneratorTests.swift
    BuildLogParserTests.swift
    ProjectIndexerTests.swift
    LatexTokenizerTests.swift
    PDFViewerStateTests.swift
    SettingsStoreTests.swift
  Integration/
    LatexmkBuildIntegrationTests.swift
    EngineMatrixIntegrationTests.swift
    BibliographyIntegrationTests.swift
    SyncTeXIntegrationTests.swift
    SandboxFileAccessIntegrationTests.swift
  UI/
    ProjectOpenBuildUITests.swift
    ErrorNavigatorUITests.swift
    PDFViewerUITests.swift
    PreferencesUITests.swift
  Fixtures/
    LaTeXProjects/
    Logs/
    Manifests/
```

## MVP 완료 기준

- Unit test가 빌드 시스템, 인덱서, 로그 파서, 편집 tokenizer의 핵심 케이스를 포함한다.
- 실제 TeX toolchain integration test가 최소 `pdflatex`, `xelatex`, BibTeX fixture를 통과한다.
- invalid LaTeX fixture에서 오류 패널이 expected issue를 표시한다.
- multi-file fixture에서 included file 오류가 정확한 파일/줄로 이동한다.
- macOS Apple Silicon과 Intel에서 기본 open/build/PDF smoke가 통과한다.
- release checklist가 문서화되고 RC마다 실행 결과가 저장된다.

## Beta/v1.0 확장

Beta에서는 SyncTeX inverse search, Biber, build profile matrix, 실제 사용자 프로젝트 QA corpus를 강화한다. v1.0에서는 Paper Diagnostics, Quick Fix, 제출 준비 체크리스트, bibliography manager까지 fixture와 UI test를 확장한다.

장기적으로는 사용자가 동의한 anonymized build failure pattern을 수집해 fixture 후보로 전환하고, 회귀 테스트가 실제 사용자의 실패 사례를 따라가도록 만든다.
