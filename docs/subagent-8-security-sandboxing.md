# Subagent 8: Security and Sandboxing Agent

PaperForge는 사용자가 선택한 LaTeX 프로젝트 폴더를 열고, 외부 TeX toolchain을 실행하며, PDF와 빌드 산출물을 생성하는 macOS native 앱이다. 이 구조는 일반 문서 편집기보다 공격 표면이 넓다. 특히 LaTeX 문서는 `\write18`, `shell-escape`, `.latexmkrc`, bibliography/index 도구, 이미지 변환 도구를 통해 외부 명령 실행으로 이어질 수 있고, macOS sandbox에서는 파일 권한이 프로세스 실행과 충돌할 수 있다.

이 문서는 App Store 배포 가능성을 유지하는 설계를 기본 목표로 하되, 초기 제품은 direct distribution을 우선 권장한다. 핵심 원칙은 사용자 의도를 명시적으로 기록하고, 프로젝트별 권한을 좁게 유지하며, 외부 명령 실행을 shell이 아닌 구조화된 `Process` 호출로 제한하는 것이다.

## Scope

포함 범위:

- macOS App Sandbox, security-scoped bookmark, Powerbox 기반 파일 권한
- 프로젝트 폴더, 포함 파일, bibliography, graphics, build directory 권한 설계
- `latexmk`, `pdflatex`, `xelatex`, `lualatex`, `bibtex`, `biber`, `makeindex`, `synctex` 등 외부 프로세스 실행 정책
- `shell-escape`, user-selected TeX binary, `.latexmkrc`, PATH/environment 보안
- Mac App Store 배포와 direct distribution 비교

비포함 범위:

- 클라우드 동기화 서버 보안
- 팀 협업/공유 권한 모델
- DRM, 라이선스 서버, 결제 보안
- 악성 TeX 문서를 완전 격리하는 VM/container 렌더링

## Security Baseline

PaperForge가 지켜야 할 기본 보안 성질은 다음과 같다.

| 목표 | 설명 | 제품 정책 |
| --- | --- | --- |
| 사용자 의도 보존 | 앱이 접근하는 프로젝트와 출력 위치는 사용자가 선택했거나 프로젝트 내부여야 한다. | `NSOpenPanel`/drag-and-drop으로 획득한 URL만 영속화한다. |
| 최소 권한 | 전체 홈 디렉터리나 Downloads 전역 권한을 요구하지 않는다. | 프로젝트 폴더 단위 read-write bookmark를 기본으로 한다. |
| 명령 실행 투명성 | 어떤 binary와 argument가 실행되는지 재현 가능해야 한다. | shell 문자열 대신 executable URL + argument array를 저장/표시한다. |
| 위험 기능 명시화 | `shell-escape`, custom binary, external output directory는 보안 경고와 프로젝트별 opt-in이 필요하다. | 기본값은 비활성이고, trusted project에서만 허용한다. |
| 산출물 격리 | aux/log/generated 파일이 소스 폴더를 오염시키거나 임의 위치에 쓰이지 않아야 한다. | 기본 build directory는 프로젝트 내부 `.paperforge-build/` 또는 앱 container cache로 제한한다. |
| 복구 가능성 | bookmark stale, 권한 거부, toolchain missing 상태가 사용자가 해결 가능한 UX로 드러나야 한다. | build issue와 permission repair flow를 제공한다. |

## Security Risk Table

| 영역 | 위협 시나리오 | 영향 | 가능성 | 위험도 | 완화책 | 잔여 위험 |
| --- | --- | --- | --- | --- | --- | --- |
| `shell-escape` | 악성 `.tex`가 `\write18` 또는 package를 통해 임의 명령을 실행한다. | 사용자 파일 삭제, credential 유출, malware 실행 | 중간 | 높음 | 기본 `-no-shell-escape`, 프로젝트별 opt-in, 경고 UI, command log, direct distribution에서도 동일 정책 | 사용자가 신뢰 프로젝트로 승인하면 OS 사용자 권한 내 피해 가능 |
| `.latexmkrc` | 프로젝트 내 `.latexmkrc`가 custom dependency command를 실행한다. | 의도치 않은 외부 프로세스 실행 | 높음 | 높음 | 기본은 `.latexmkrc` 감지 후 경고, trusted project에서만 활성화, 위험 command preview | latexmk 자체 기능이 넓어 완전 정적 검증 어려움 |
| PATH hijacking | 공격자가 프로젝트 폴더에 `pdflatex`/`bibtex` 같은 이름의 binary를 두고 PATH 앞부분에 삽입되게 한다. | 악성 binary 실행 | 중간 | 높음 | absolute executable URL 사용, PATH에서 프로젝트 폴더 제외, `/Library/TeX/texbin` 우선, binary identity cache | 사용자가 custom path를 승인하면 검증 한계 존재 |
| user-selected TeX binary | 사용자가 악성 또는 변조된 TeX binary를 선택한다. | 앱이 악성 코드 실행 launcher가 됨 | 낮음-중간 | 높음 | 선택 시 signature/quarantine/path 표시, bundle/container 내부 binary 금지, 프로젝트별이 아닌 앱 설정에 저장, 변경 시 재확인 | 사용자가 직접 승인한 binary는 실행 가능 |
| build directory traversal | 설정된 output/aux directory가 프로젝트 밖 민감 위치를 가리킨다. | 임의 파일 덮어쓰기, 정보 유출 | 중간 | 높음 | 기본 `.paperforge-build/`, 외부 output은 별도 folder permission 필요, symlink/canonical path 검사 | TeX tool이 내부적으로 쓰는 경로는 완전 통제 어려움 |
| symlink abuse | 프로젝트 내부 파일이 symlink로 홈 디렉터리의 민감 파일을 가리킨다. | 파일 읽기/쓰기 확대 | 중간 | 중간-높음 | write 대상 canonical path 검증, 외부 symlink 쓰기 전 경고, indexer는 symlink cycle 제한 | TeX engine의 파일 접근은 sandbox 여부에 따라 달라짐 |
| sandbox child process | sandboxed 앱의 child process가 동적 Powerbox 권한을 자동 상속하지 못한다. | 빌드 실패, 권한 오류 | 높음 | 중간 | 빌드 실행 전 필요한 파일을 project root 아래로 제한, bookmark resolve 후 working directory 설정, helper에는 bookmark/pass-through 전략 | 외부 TeX tool의 세부 접근 패턴을 모두 예측하기 어려움 |
| unrestricted file access in direct build | non-sandboxed direct 배포 앱이 사용자 홈 전체에 접근 가능하다. | 악성 문서+shell escape 조합 피해 증가 | 중간 | 높음 | direct 배포에서도 PaperForge 자체 정책으로 접근 범위와 명령을 제한, hardened runtime/notarization | OS sandbox가 없으므로 앱 버그 피해 범위가 넓음 |
| bibliography/index tools | `biber`, `bibtex`, `makeindex`, `makeglossaries` 등이 파일을 읽고 생성한다. | 예상 밖 파일 접근/생성 | 중간 | 중간 | allowlist toolchain, argument normalization, output directory 제한, logs 표시 | tool 자체 취약점 또는 package별 동작 차이 |
| SyncTeX command | `synctex` 실행 시 source/PDF 경로가 외부 파일을 참조한다. | 권한 오류, 잘못된 파일 reveal | 낮음 | 중간 | SyncTeX 결과를 project root 또는 granted file로 제한, 외부 source는 사용자 확인 | 오래된 `.synctex.gz`의 path mismatch |
| bookmark persistence | 오래된 security-scoped bookmark가 stale 또는 invalid가 된다. | 최근 프로젝트 열기 실패, 데이터 접근 실패 | 중간 | 중간 | stale 감지 후 재생성, permission repair UI, URL path fallback은 read-only 표시 | OS 업데이트/이동/권한 변경으로 재승인 필요 |
| bookmark leakage | bookmark data가 평문 설정 파일에서 유출된다. | 사용자의 승인 위치 정보 노출, 일부 접근 토큰 남용 가능성 | 낮음 | 중간 | Application Support 저장, file protection/권한, 민감 로그 제외, project document에는 document-scoped만 | 로컬 계정 compromise 시 보호 한계 |
| generated executable | TeX/package가 script 또는 binary를 생성하고 실행하려 한다. | Gatekeeper 우회 시도 또는 악성 실행 | 낮음-중간 | 높음 | App Store build에서 `user-selected.executable` entitlement 회피, build output executable 실행 금지, shell escape off | custom trusted build에서는 사용자 책임 영역 |
| network access | TeX package나 shell escape command가 network를 사용한다. | 문서 내용/경로 유출 | 낮음-중간 | 중간 | PaperForge 자체는 기본 network client entitlement 불필요, shell escape 경고에 network risk 명시 | 외부 binary가 OS 권한으로 network 사용 가능 |
| iCloud/Dropbox sync | 빌드 중 동기화가 aux/log/pdf 파일을 잠그거나 교체한다. | 빌드 실패, stale PDF, 권한 오류 | 중간 | 낮음-중간 | atomic write 감지, reload retry, build dir 내부 격리, permission diagnostics | 클라우드 provider별 race condition |

## Sandboxing Strategy

### Recommendation

아키텍처는 sandbox-compatible로 설계한다. 즉, 파일 접근과 외부 실행을 `FileAccessService`, `SecurityScopeManager`, `ProcessRunner` 뒤에 숨기고, App Store build와 direct build가 같은 상위 정책을 공유한다.

초기 상용 배포는 direct distribution + Developer ID signing + notarization을 권장한다. 동시에 CI에 sandboxed build flavor를 유지해 App Store 가능성을 검증한다.

### App Store Sandboxed Build

필수 entitlements:

| Entitlement | 용도 | 권장 |
| --- | --- | --- |
| `com.apple.security.app-sandbox` | App Sandbox 활성화 | App Store build 필수 |
| `com.apple.security.files.user-selected.read-write` | 사용자가 선택한 프로젝트 폴더 read-write | 필수 |
| `com.apple.security.files.bookmarks.app-scope` | 최근 프로젝트/툴체인 위치 persistent access | 필수 |
| `com.apple.security.files.bookmarks.document-scope` | 프로젝트 문서 안에 상대 bookmark 저장 시 사용 | Beta 이후 검토 |
| `com.apple.security.inherit` | bundled child helper가 sandbox를 상속할 때 helper target에만 사용 | helper 사용 시 |
| `com.apple.security.network.client` | 업데이트 체크, package lookup, AI 기능 등 네트워크 기능 | MVP에서는 끄고 필요 시 기능별 enable |
| `com.apple.security.files.user-selected.executable` | 앱이 command-line executable을 생성해야 할 때 | 기본 비권장 |

Sandboxed build의 실행 모델:

1. 사용자가 프로젝트 폴더를 선택한다.
2. 앱은 project root에 대한 security-scoped bookmark를 생성해 `BookmarkStore`에 저장한다.
3. 프로젝트를 열 때 bookmark를 resolve하고 `startAccessingSecurityScopedResource()` scope 안에서 indexing/build/PDF reload를 수행한다.
4. 빌드 working directory는 project root로 설정하되, output/aux는 project root 내부 `.paperforge-build/`로 제한한다.
5. 외부 TeX binary는 absolute path로 실행한다. 앱은 shell을 호출하지 않는다.
6. child process가 동적 file grant를 상속하지 못하는 케이스에 대비해, build helper를 도입한다면 bookmark 또는 필요한 file data를 명시적으로 전달한다.

Sandboxed build에서 특히 주의할 점:

- macOS sandbox의 Powerbox 권한은 사용자의 선택에 의해 확장되지만, child process가 모든 동적 권한을 기대대로 상속한다고 가정하면 안 된다.
- App Store 심사 관점에서 "사용자가 선택한 프로젝트를 컴파일하는 문서 앱"은 설명 가능하지만, "임의 shell command runner"처럼 보이면 리젝 위험이 커진다.
- `.latexmkrc`와 `shell-escape`는 기능적으로 중요하더라도 보안 위험 기능으로 분리해야 한다.
- `/Library/TeX/texbin` 접근과 실행 자체는 가능하더라도, TeX process가 접근하려는 입력/출력 파일은 sandbox 권한 설계에 영향을 받는다.

### Direct Distribution Build

Direct build는 App Sandbox를 끌 수 있다. 장점은 MacTeX/TeX Live, Homebrew, custom scripts, external output directory와의 호환성이 높다는 점이다. 단점은 PaperForge 프로세스와 외부 TeX 프로세스가 사용자 권한으로 넓은 파일 시스템 접근을 갖는다는 점이다.

Direct build에서도 다음 정책은 sandboxed build와 동일하게 유지한다.

- shell 실행 금지: `/bin/sh -c` 또는 user-supplied command string 실행 금지
- `shell-escape` 기본 비활성
- executable path는 absolute URL로 저장
- project root 외부 output directory는 사용자 선택 필요
- 빌드 로그에 executable, arguments, cwd, environment 요약 표시
- TeX binary 변경, `.latexmkrc` 활성화, shell escape 활성화는 별도 확인

Direct distribution은 Developer ID signing, hardened runtime, notarization을 기본 릴리스 절차로 포함해야 한다. Mac App Store를 통하지 않는 앱도 Gatekeeper 신뢰 경로를 확보해야 하며, notarization 실패 시 배포를 중단한다.

## File Permission Strategy

### Permission Model

PaperForge의 파일 권한 단위는 "프로젝트 폴더"를 기본으로 한다.

| 리소스 | 권한 획득 방식 | 저장 방식 | 정책 |
| --- | --- | --- | --- |
| 프로젝트 root | `NSOpenPanel` directory 선택 또는 drag-and-drop | app-scoped security-scoped bookmark | read-write 필수 |
| 단일 `.tex` 파일 | `NSOpenPanel` file 선택 | 파일 bookmark + parent folder 재요청 권장 | 단일 파일 편집은 가능하나 빌드는 parent folder 권한 요구 |
| included `.tex`/`.bib`/image | project root 하위이면 자동 접근 | 별도 저장 없음 | root 밖이면 missing permission issue 생성 |
| external bibliography/image | 사용자 확인 후 파일 또는 parent folder 선택 | app-scoped bookmark | project-relative 경로 전환 권장 |
| build directory | 기본 project root 하위 `.paperforge-build/` | project permission에 포함 | 외부 위치는 별도 folder bookmark 필요 |
| TeX binary path | 자동 감지 또는 user selection | path + optional bookmark + identity metadata | executable 검증 후 저장 |
| PDF export/save as | `NSSavePanel` | 필요 시 recent export bookmark | 사용자가 선택한 위치만 write |

### Security-Scoped Bookmark Lifecycle

`SecurityScopeManager`는 다음 동작을 제공한다.

```swift
protocol SecurityScopeManaging {
    func grantProjectAccess(url: URL) throws -> FilePermissionGrant
    func resolveGrant(_ grant: FilePermissionGrant) throws -> ScopedURL
    func refreshGrantIfNeeded(_ grant: FilePermissionGrant) async throws -> FilePermissionGrant
    func revokeGrant(_ grantID: UUID) throws
}
```

구현 원칙:

- bookmark data는 `Application Support/PaperForge/Bookmarks.json` 또는 SQLite에 저장한다.
- bookmark resolve 시 stale flag를 확인하고, stale이면 가능한 즉시 새 bookmark를 저장한다.
- `startAccessingSecurityScopedResource()`와 `stopAccessingSecurityScopedResource()`는 scope object로 짝을 맞춘다.
- long-running build 동안 project root scope는 유지한다.
- scope leak 방지를 위해 `defer` 또는 RAII 스타일 wrapper를 사용한다.
- bookmark data, resolved absolute path, user name이 포함된 값은 crash log와 analytics에 보내지 않는다.

예상 에러와 UX:

| 상태 | 감지 | 사용자 메시지 방향 | 복구 |
| --- | --- | --- | --- |
| bookmark stale | resolve stale flag | 프로젝트 권한을 갱신해야 함 | 같은 폴더 재선택 |
| permission denied | file read/write error | macOS 권한이 만료되었거나 폴더가 이동됨 | repair permission 버튼 |
| external include blocked | index/build log path가 root 밖 | 외부 파일 접근 권한 필요 | 파일 또는 parent folder 선택 |
| build dir unwritable | create directory/write test 실패 | 빌드 폴더에 쓸 수 없음 | 기본 build dir 재설정 또는 다른 폴더 선택 |
| symlink outside root | canonical path 검사 | 프로젝트 밖 링크 파일 감지 | read-only 처리 또는 명시 승인 |

### Path and Symlink Policy

모든 파일 작업은 세 가지 path를 구분한다.

| Path 종류 | 용도 |
| --- | --- |
| Display path | UI 표시용, `~` 축약 가능 |
| Stored bookmark URL | 권한 복구용, raw absolute path에 의존하지 않음 |
| Canonical file URL | 보안 검사와 root containment 판정용 |

정책:

- write 작업 전 `resolvingSymlinksInPath()`와 file resource identifier를 이용해 project root containment를 확인한다.
- symlink가 project root 밖을 가리키면 indexing은 허용하되 build input으로 사용할 때 경고한다.
- generated file write는 build directory 하위로 제한한다.
- TeX source save는 사용자가 연 원본 URL에만 수행한다.
- automatic cleanup은 `.paperforge-build/` 하위에서만 수행한다.

## Build Directory Permission Strategy

기본 build directory:

```text
<project-root>/.paperforge-build/
```

대안:

```text
~/Library/Containers/<bundle-id>/Data/Library/Caches/PaperForge/Builds/<workspace-id>/
```

권장 기본값은 project root 내부 `.paperforge-build/`이다. 이유는 TeX toolchain이 상대 경로와 auxiliary file을 많이 사용하고, 사용자가 프로젝트를 압축/이동할 때 빌드 상태를 이해하기 쉽기 때문이다. 단, iCloud Drive 프로젝트에서는 동기화 소음이 커질 수 있으므로 "App cache build directory" 옵션을 제공한다.

정책:

- `.paperforge-build/`는 앱이 생성하고 `.gitignore` 제안을 제공한다.
- cleanup은 build directory 내부만 대상으로 하며, symlink를 따라 삭제하지 않는다.
- output PDF는 기본적으로 build directory에 생성하고 viewer가 이를 표시한다.
- 사용자가 source root 옆에 `main.pdf`를 원하면 "Copy final PDF to project root" 옵션으로 별도 복사한다.
- 외부 output directory는 `NSOpenPanel`/`NSSavePanel`로 권한을 얻고 bookmark를 저장한다.

삭제 안전장치:

- cleanup 대상 root에 PaperForge marker file을 둔다: `.paperforge-build/.paperforge-owned`
- marker가 없으면 자동 삭제를 거부한다.
- recursive delete 전 canonical path가 project root 하위 또는 app container cache 하위인지 확인한다.
- build directory path가 `/`, home, Documents, Downloads, Desktop, project root 자체이면 거부한다.

## External Command Execution Policy

### Command Runner Contract

외부 명령 실행은 단일 `ProcessRunner`로만 수행한다.

```swift
struct ExternalCommand {
    var executable: URL
    var arguments: [String]
    var workingDirectory: URL
    var environment: [String: String]
    var allowedInputRoots: [URL]
    var allowedOutputRoot: URL
    var riskLevel: CommandRiskLevel
}
```

절대 금지:

- `/bin/sh -c "<user string>"` 실행
- project file에서 읽은 command line을 그대로 split해서 실행
- current directory 또는 project directory를 PATH 앞에 추가
- untrusted `.latexmkrc`를 조용히 활성화
- build output cleanup에서 arbitrary path 삭제

필수:

- executable은 absolute path여야 한다.
- arguments는 array로 전달하고 shell quoting을 요구하지 않는다.
- environment는 최소화한다.
- `PATH`는 PaperForge가 구성한 고정 목록으로 제한한다.
- `cwd`는 project root 또는 build directory로 제한한다.
- stdout/stderr는 크기 제한과 redaction을 적용해 캡처한다.
- timeout, cancellation, process group termination을 지원한다.

### Allowed Tools

기본 allowlist:

| Tool | 기본 허용 | 조건 |
| --- | --- | --- |
| `latexmk` | 예 | absolute path, PaperForge-generated arguments |
| `pdflatex` | 예 | fallback/direct engine |
| `xelatex` | 예 | fallback/direct engine |
| `lualatex` | 예 | fallback/direct engine |
| `bibtex` | 예 | build profile 또는 latexmk가 필요로 할 때 |
| `biber` | 예 | build profile 또는 log 감지 후 사용자 확인 |
| `makeindex` | 예 | index/glossary profile |
| `synctex` | 예 | PDF/source navigation only |
| `kpsewhich` | 예 | tool discovery, package lookup |
| `python`, `ruby`, `perl`, `node`, `bash`, `zsh`, `make` | 기본 아니오 | trusted project + explicit custom command policy 필요 |
| `inkscape`, `gnuplot`, `pygmentize`, `latexminted` | 기본 아니오 | feature-specific opt-in, path 검증, shell escape 안내 필요 |

MVP에서는 custom command runner를 제공하지 않는다. "사용자 지정 recipe"는 executable dropdown과 argument template의 제한된 조합으로 시작하고, arbitrary shell script support는 direct distribution의 advanced setting으로 미룬다.

### TeX Binary Discovery

자동 감지 순서:

1. 사용자 설정에 저장된 TeX distribution path
2. `/Library/TeX/texbin`
3. `/usr/local/texlive/*/bin/universal-darwin` 또는 platform-specific bin
4. `/opt/homebrew/bin`, `/usr/local/bin`
5. `/usr/bin/env`를 통한 PATH 탐색은 진단용으로만 사용하고, 최종 실행은 resolved absolute path로 수행

저장 metadata:

| 항목 | 목적 |
| --- | --- |
| absolute path | 실행 대상 고정 |
| resolved real path | symlink 변경 감지 |
| file size/mtime | 변경 감지 |
| code signature summary | 변조/출처 표시 |
| quarantine xattr 여부 | 다운로드 binary 경고 |
| detected version output | 사용자 진단 |

변경 감지:

- 저장된 binary의 real path, signature, mtime이 바뀌면 "Toolchain changed" 경고를 표시한다.
- 프로젝트별로 binary를 override할 수 있게 하되, 기본은 앱 전역 toolchain을 사용한다.
- 프로젝트 폴더 내부 binary는 기본 거부한다. 허용하려면 advanced confirmation이 필요하다.

## Shell Escape Policy

기본값:

```text
-no-shell-escape
```

정책:

| Mode | UI 명칭 | 허용 조건 | 실행 옵션 |
| --- | --- | --- | --- |
| Disabled | Shell escape 끔 | 기본 | `-no-shell-escape` |
| TeX restricted default | TeX 배포판 제한 모드 | Beta 이후 검토 | 명시 옵션 없이 TeX 기본값 사용 또는 엔진별 restricted option |
| Enabled | Shell escape 켬 | trusted project + per-project confirmation | `-shell-escape` |

MVP에서는 Disabled와 Enabled만 제공한다. Enabled는 다음 조건을 모두 만족해야 한다.

- 프로젝트 폴더가 사용자 선택 bookmark로 열려 있음
- `.paperforge/project-security.json` 또는 앱 설정에 project identity별 승인 기록
- 승인 UI에 위험 설명, 실행될 TeX binary, project root, build directory 표시
- remote/template 프로젝트에서 처음 열릴 때 자동 활성화 금지
- build log에 `shellEscape: enabled` 기록

승인 문구의 핵심:

```text
이 옵션은 LaTeX 문서가 TeX 빌드 중 외부 프로그램을 실행할 수 있게 합니다.
신뢰하는 프로젝트에서만 켜세요.
```

`.latexmkrc` 정책:

- `.latexmkrc`가 project root 또는 parent directories에서 발견되면 build panel에 표시한다.
- 기본은 project root의 `.latexmkrc`만 고려하고, home directory global `.latexmkrc`는 무시하거나 사용자 설정으로만 허용한다.
- `.latexmkrc` 활성화는 shell escape와 별도의 trusted project flag로 관리한다.
- `.latexmkrc`가 custom dependency, `$pdflatex`, `$postscript_mode`, `$cleanup_includes_cusdep_generated` 등을 설정하면 risk level을 올린다.

## External Commands and App Store Review

Mac App Store 관점의 리스크:

| 기능 | App Store 적합성 | 리스크 | 대응 |
| --- | --- | --- | --- |
| 사용자 선택 프로젝트 컴파일 | 가능성 높음 | 외부 toolchain 의존 | TeX 미설치 UX와 user-selected path 설명 |
| `latexmk`/TeX binary 실행 | 가능하지만 심사 설명 필요 | sandbox child process, arbitrary command 오해 | fixed allowlist와 no shell policy 문서화 |
| `.latexmkrc` 실행 | 민감 | arbitrary command runner로 보일 수 있음 | 기본 off, trusted project only |
| `shell-escape` | 매우 민감 | 악성 command 실행 가능 | 기본 off, advanced opt-in, App Store build에서는 제한 또는 숨김 검토 |
| custom shell command recipe | 낮음 | 일반 shell runner 기능으로 해석 가능 | App Store build에서는 미제공 권장 |
| executable 생성 | 낮음 | `user-selected.executable` entitlement 필요 가능 | MVP 비지원 |
| bundled TeX distribution | 가능하지만 무거움 | 번들 크기, 라이선스, 업데이트, 심사 | MVP 비권장 |

App Store build profile 권장:

- sandbox on
- shell escape feature는 "프로젝트별 고급 옵션"으로 숨기거나 Beta에서는 제거
- custom command recipe 제거
- `.latexmkrc` 기본 off
- external output directory는 user-selected folder만 허용
- toolchain path는 user selection 또는 known TeX distribution path로 제한
- 앱 내 설명/리뷰 노트에 "PaperForge invokes user-installed TeX tools only to compile user-selected documents" 명시

Direct build profile 권장:

- sandbox optional 또는 off
- shell escape advanced opt-in 제공
- `.latexmkrc` trusted project opt-in 제공
- custom recipe는 제한된 executable+arguments 방식으로 제공
- notarized Developer ID 배포
- release notes에 external tool execution model 투명하게 설명

## App Store vs Direct Distribution Recommendation

| 기준 | Mac App Store | Direct Distribution |
| --- | --- | --- |
| 사용자 신뢰 | App Store 심사와 설치 UX 장점 | Developer ID/notarization으로 기본 신뢰 확보 가능 |
| 파일 권한 | sandbox 필수에 가까워 권한 UX 필요 | 권한 마찰 적음 |
| TeX 호환성 | 외부 toolchain, `.latexmkrc`, shell escape에서 제약 큼 | 기존 LaTeX workflow와 호환성 높음 |
| 보안 | OS sandbox로 피해 범위 축소 | 앱 자체 정책과 hardened runtime에 의존 |
| 업데이트 속도 | 리뷰 지연 가능 | 빠른 hotfix 가능 |
| 결제/라이선스 | App Store 정책과 수수료 | 자체 결제, 기관 라이선스 유연 |
| 엔터프라이즈/연구실 | 관리형 배포에 제약 가능 | DMG/PKG, MDM, license key 유리 |
| App Review 리스크 | shell escape/custom command 때문에 중간-높음 | notarization 중심, 기능 제약 적음 |

권장 결론:

1. MVP와 초기 유료 Beta는 direct distribution을 기본 채널로 한다.
2. 코드 구조는 App Store sandbox를 지원하도록 처음부터 추상화한다.
3. App Store 버전은 기능 제한판으로 별도 build flavor를 만든다.
4. App Store 제출 여부는 shell escape 없이도 충분한 가치가 입증된 뒤 결정한다.

이유:

- PaperForge의 핵심 사용자는 기존 MacTeX/TeX Live 프로젝트, `.latexmkrc`, bibliography/index 도구, minted/gnuplot/inkscape 같은 외부 도구를 이미 쓰는 경우가 많다.
- 이 사용자층에게 App Store sandbox 제약은 초기 제품 만족도를 낮출 가능성이 크다.
- direct distribution은 빠른 업데이트, 고급 빌드 옵션, 기관 라이선스에 유리하다.
- 그러나 장기적으로 App Store 검색/신뢰 채널도 가치가 있으므로 sandbox-compatible architecture는 포기하지 않는다.

## Implementation Plan

### Phase 1: Security Foundation

- `FileAccessService`, `SecurityScopeManager`, `BookmarkStore` 인터페이스 확정
- project root bookmark 저장/resolve/refresh 구현
- `.paperforge-build/` 생성, marker file, cleanup guard 구현
- `ProcessRunner` 단일 진입점 도입
- executable URL + arguments 기반 command model 적용
- `-no-shell-escape` 명시
- PATH allowlist와 project directory PATH exclusion 적용

### Phase 2: Toolchain and Permission Diagnostics

- TeX binary discovery 및 identity metadata 저장
- missing executable, permission denied, stale bookmark diagnostic issue 추가
- external include 감지와 permission repair flow 추가
- symlink outside root 감지
- build log에 command summary 표시

### Phase 3: Trusted Project Features

- project security settings 추가: `.paperforge/project-security.json`
- shell escape opt-in UI
- `.latexmkrc` opt-in UI
- custom TeX binary 변경 경고
- external output directory permission flow

### Phase 4: Distribution Profiles

- Direct profile: sandbox off, hardened runtime on, notarization CI
- App Store profile: sandbox on, custom command disabled, shell escape hidden/limited
- Review notes template 작성
- sandbox smoke test suite 추가

## Test Matrix

| 테스트 | Direct | Sandboxed | 기대 결과 |
| --- | --- | --- | --- |
| project root 열기/재실행 | 필수 | 필수 | 최근 프로젝트가 재오픈됨 |
| bookmark stale simulation | 해당 없음 또는 선택 | 필수 | repair permission flow 표시 |
| `.paperforge-build/` 생성 | 필수 | 필수 | marker file 생성, PDF/log 저장 |
| build dir cleanup | 필수 | 필수 | marker 없는 directory 삭제 거부 |
| symlink to outside file | 필수 | 필수 | 경고 또는 명시 승인 필요 |
| missing external image | 필수 | 필수 | permission issue 표시 |
| `-no-shell-escape` compile | 필수 | 필수 | shell escape 필요한 문서는 안전하게 실패 |
| shell escape opt-in | 필수 | App Store profile에서는 제한 | 승인 후에만 옵션 추가 |
| `.latexmkrc` present | 필수 | 필수 | 기본 경고, opt-in 전 비활성 |
| PATH hijack fixture | 필수 | 필수 | project-local fake binary 미실행 |
| custom TeX binary | 필수 | 선택 | identity 표시와 재확인 |
| iCloud project build | 필수 | 필수 | permission 유지, PDF reload retry |
| App notarization | 필수 | 해당 없음 | CI release gate |
| App Store sandbox archive | 선택 | 필수 | entitlement와 review profile 검증 |

## Review Notes Template

App Store 제출 시 reviewer note 초안:

```text
PaperForge is a macOS LaTeX editor. It opens only user-selected project folders and stores security-scoped bookmarks for recently opened projects. The app invokes user-installed TeX tools such as latexmk, pdflatex, xelatex, and lualatex only to compile the user's selected documents. Commands are executed through Process with fixed executable paths and argument arrays; the app does not expose a general shell command runner. Shell escape and project latexmk configuration are disabled by default and require explicit per-project user confirmation.
```

## Open Questions

- App Store build에서 `shell-escape`를 완전히 제거할지, advanced opt-in으로 남길지 결정 필요
- sandboxed child process가 `/Library/TeX/texbin` 및 TeX 하위 script를 실행하는 실제 호환성 테스트 필요
- BasicTeX/MacTeX/Homebrew TeX Live별 executable discovery와 code signature metadata 차이 확인 필요
- `.latexmkrc`를 무시하는 latexmk 옵션/환경 구성이 안정적으로 가능한지 검증 필요
- minted 최신 버전의 `latexminted` 및 TeX Live restricted shell escape 변화에 맞춘 별도 compatibility policy 필요

## Sources

- Apple Developer Documentation, "Accessing files from the macOS App Sandbox"
- Apple Entitlement Key Reference, "Enabling App Sandbox"
- Apple Developer Documentation, "Embedding a command-line tool in a sandboxed app"
- Apple Developer Documentation, "Notarizing macOS software before distribution"
- Apple App Review Guidelines
- TeX Live Guide 2026, shell escape and restricted shell execution notes
