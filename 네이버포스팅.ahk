#Requires AutoHotkey v2.0
#SingleInstance Force

; 네이버 블로그 자동 타이핑
; 마크다운 글을 커서가 놓인 자리에 실제 키 입력으로 쳐 넣는다.
;
;  [브라우저 창에서만 동작]
;   F9   제목 타이핑   (제목칸 클릭해서 커서 두고 누르기)
;   F10  본문 타이핑   (본문 클릭해서 커서 두고 누르기)
;   F11  다른 글 파일 선택 (고르면 그 글에 고정)
;   Esc  타이핑 중단 (마우스 클릭 · 다른 창으로 넘어가도 멈춘다)
;        멈춘 자리는 기억해 둔다. 커서를 글 끝에 두고 F9/F10 을 다시 누르면
;        "이어서 / 처음부터" 를 묻고, 이어서를 고르면 멈춘 다음 글자부터 친다.
;
;  [Claude 가 쓴 글 자동으로 받기]
;   Claude 에게 "블로그 글 써줘" 하면 GitHub 저장소 posts/ 에 올라온다.
;   이 스크립트가 1분마다 받아와 옵시디언 네이버블로그\Claude 폴더에 저장하고,
;   옵시디언에서 열어 준 뒤 네이버 글쓰기 창을 열지 묻는다. 그 글이 곧 F9/F10 대상이 된다.
;   Ctrl+Alt+S  지금 바로 받기
;   (sync-posts.ps1 을 이 스크립트 옆에 두고, PC 에 git 이 깔려 있어야 한다)
;
;  [서식 유지가 필요할 때 - 붙여넣기 방식]
;   Ctrl+Alt+1  제목 붙여넣기
;   Ctrl+Alt+2  본문 붙여넣기 (소제목/굵게/표 살아 있음)
;   Ctrl+Alt+3  태그 클립보드로
;   Ctrl+Alt+0  다른 글 파일 선택
;   Ctrl+Alt+9  최신 글 자동 추적으로 되돌리기
;   Ctrl+Alt+Q  종료
;
; 좌표 클릭은 쓰지 않는다. 제목을 넣으면 제목칸 높이가 늘어나
; 본문 좌표가 밀려서 본문이 제목칸에 들어가 버린다.

PS_PATH  := A_ScriptDir "\md2clip.ps1"
; 글이 저장되는 곳. 이 아래에서 가장 최근에 저장된 .md 를 자동으로 잡는다.
POST_DIRS := ["C:\Users\jhm58\OneDrive\Documents\ClaudeVault\네이버블로그"
            , "C:\Users\jhm58\OneDrive\바탕 화면\블로그 포스팅"]
SKIP_DIRS := ["_자동화", "_시스템", "reference", ".obsidian", ".trash"]
CurFile  := ""
Pinned   := false      ; F11 로 직접 고르면 true. 그 전까지는 항상 최신 글을 따라간다.
Typing   := false      ; 타이핑 중에는 글 받기를 쉰다 (창이 뜨면 타이핑이 끊긴다)

; Claude 가 쓴 글을 받아올 곳
SYNC_PS    := A_ScriptDir "\sync-posts.ps1"
REPO_URL   := "https://github.com/jeonghyemin9233-maker/-.git"
REPO_DIR   := A_AppData "\네이버포스팅\repo"   ; 저장소 사본. 처음 한 번 자동으로 받는다
INBOX_DIR  := POST_DIRS[1] "\Claude"           ; 받은 글을 저장할 옵시디언 폴더
SYNC_EVERY := 60000                             ; 몇 ms 마다 확인할지
WRITE_URL  := "https://blog.naver.com/GoBlogWrite.naver"   ; 네이버 블로그 글쓰기
SyncErrShown := false

; 사람 타자 리듬 손잡이. 전체적으로 빠르면 CHAR_MIN/MAX 를 올린다.
; 기준: 글자당 평균 90ms ≈ 분당 660타 정도의 체감.
CHAR_MIN    := 55     ; 글자당 최소 간격(ms)
CHAR_MAX    := 130    ; 글자당 최대 간격(ms)
SENT_PAUSE  := 400    ; 문장 끝(. ! ?) 에서 추가로 쉬는 시간
COMMA_PAUSE := 130    ; 쉼표에서 추가로 쉬는 시간
LINE_PAUSE  := 550    ; 줄을 바꾼 뒤 쉬는 시간
THINK_ODDS  := 45     ; 이 확률(1/45)로 잠깐 멈칫한다. 0 이면 끔

; 멈춘 자리. 제목("title")·본문("body") 따로 {file, pos, ctx} 로 둔다.
; ctx 는 멈추기 직전에 친 글자들 — 멈춘 뒤 글을 고쳐도 이걸로 자리를 다시 찾는다.
Resume     := Map()
RESUME_CTX := 40

TraySetIcon("shell32.dll", 70)
A_IconTip := "네이버포스팅 (대기 중)"
BuildTray()
SetTimer(() => SyncPosts(), -3000)
SetTimer(() => SyncPosts(), SYNC_EVERY)
; 부팅마다 파일 선택 창이 뜨면 성가시므로 조용히 대기한다.
; 글 파일은 F9/F10 을 처음 누를 때 물어본다.

BuildTray() {
    tm := A_TrayMenu
    tm.Delete()
    tm.Add("글 파일 선택`tF11", (*) => PickFile())
    tm.Add("최신 글 자동 추적`tCtrl+Alt+9", (*) => Unpin())
    tm.Add("Claude 글 지금 받기`tCtrl+Alt+S", (*) => SyncPosts(true))
    tm.Add()
    tm.Add("사용법 보기", (*) => ShowHelp())
    tm.Add("종료", (*) => ExitApp())
    tm.Default := "글 파일 선택`tF11"
}

ShowHelp() {
    global CurFile
    MsgBox("브라우저(네이버 글쓰기) 창에서만 동작합니다.`n`n"
         . "  F9   제목칸 클릭 후 누르면 제목 타이핑`n"
         . "  F10  본문 클릭 후 누르면 본문 타이핑`n"
         . "  F11  다른 글 파일 선택 (고른 글에 고정)`n"
         . "  Ctrl+Alt+9  최신 글 자동 추적으로 되돌리기`n"
         . "  Esc  타이핑 중단 (클릭하거나 다른 창으로 가도 멈춤)`n"
         . "       → 커서를 글 끝에 두고 F9/F10 다시 누르면 멈춘 곳부터 이어서`n`n"
         . "  Ctrl+Alt+2  본문 붙여넣기 (서식 유지, 빠름)`n"
         . "  Ctrl+Alt+3  태그 클립보드로`n"
         . "  Ctrl+Alt+S  Claude 가 쓴 글 지금 받기 (1분마다 자동)`n`n"
         . "현재 글: " (CurFile = "" ? "(선택 안 됨)" : RegExReplace(CurFile, ".*\\")),
           "네이버포스팅 사용법")
}

; ---------- 글 파일 ----------

; 두 보관 폴더를 통틀어 가장 최근에 저장된 글. 방금 쓴 글이 여기 걸린다.
NewestMd() {
    global POST_DIRS, SKIP_DIRS
    best := "", bestT := 0
    for dir in POST_DIRS {
        if !DirExist(dir)
            continue
        Loop Files, dir "\*.md", "R" {
            skip := false
            for sd in SKIP_DIRS
                if InStr(A_LoopFileDir, "\" sd)
                    skip := true
            if skip
                continue
            t := A_LoopFileTimeModified + 0
            if (t > bestT) {
                bestT := t
                best  := A_LoopFileFullPath
            }
        }
    }
    return best
}

; 고정(F11)해 두지 않았으면 누를 때마다 최신 글로 갈아탄다.
EnsureFile() {
    global CurFile, Pinned
    if !Pinned {
        f := NewestMd()
        if (f != "" && f != CurFile) {
            CurFile := f
            A_IconTip := "네이버포스팅(최신): " RegExReplace(f, ".*\\")
            TrayTip("최신 글을 잡았습니다", RegExReplace(f, ".*\\"))
        }
    }
    if (CurFile != "" && FileExist(CurFile))
        return true
    return PickFile()
}

Unpin() {
    global CurFile, Pinned
    Pinned  := false
    CurFile := ""
    A_IconTip := "네이버포스팅 (최신 글 자동)"
    TrayTip("이제 가장 최근에 저장된 글을 따라갑니다", "네이버포스팅")
}

PickFile() {
    global CurFile, Pinned, POST_DIRS
    SplitPath(CurFile, , &curDir)
    start := (curDir != "") ? curDir : POST_DIRS[1]
    f := FileSelect(3, start "\", "포스팅할 마크다운 파일 선택", "Markdown (*.md)")
    if (f = "")
        return (CurFile != "")          ; 취소해도 상주는 유지
    CurFile := f
    Pinned  := true                     ; 직접 골랐으면 그 글에 고정
    A_IconTip := "네이버포스팅: " RegExReplace(f, ".*\\")
    TrayTip("제목칸 클릭 후 F9 / 본문 클릭 후 F10", RegExReplace(f, ".*\\"))
    return true
}

; 마크다운의 한 부분을 클립보드에 올린다. 성공하면 true.
; (평문은 클립보드의 텍스트 형식, 서식본은 HTML 형식으로 함께 올라간다)
LoadClip(part, label) {
    global PS_PATH, CurFile
    if !EnsureFile()                     ; 고정 안 했으면 가장 최근에 저장된 글을 쓴다
        return false
    if !FileExist(CurFile) {
        MsgBox("글 파일을 찾을 수 없습니다:`n" CurFile "`n`nF11 로 다시 선택하세요.")
        return false
    }
    A_Clipboard := ""
    cmd := 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' PS_PATH '"'
         . ' -Path "' CurFile '" -Part ' part
    RunWait(cmd, A_ScriptDir, "Hide")
    if !ClipWait(5, 1) {
        MsgBox("변환 실패: " label "`n글 파일이 UTF-8 인코딩인지 확인하세요.")
        return false
    }
    return true
}

; ---------- Claude 가 쓴 글 받기 ----------

; GitHub 에 올라온 새 글을 옵시디언으로 가져온다. manual 이면 결과를 항상 알려 준다.
SyncPosts(manual := false) {
    global SYNC_PS, REPO_URL, REPO_DIR, INBOX_DIR, Typing, SyncErrShown
    static busy := false
    if (busy || Typing)
        return
    if !FileExist(SYNC_PS) {
        if manual
            MsgBox("sync-posts.ps1 이 없습니다:`n" SYNC_PS, "네이버포스팅")
        return
    }
    busy := true
    out := A_Temp "\네이버포스팅_sync.txt"
    try FileDelete(out)
    RunWait('powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' SYNC_PS '"'
          . ' -RepoUrl "' REPO_URL '" -RepoDir "' REPO_DIR '"'
          . ' -VaultDir "' INBOX_DIR '" -OutFile "' out '"', A_ScriptDir, "Hide")
    busy := false
    txt := FileExist(out) ? Trim(FileRead(out, "UTF-8"), " `r`n") : ""

    if (SubStr(txt, 1, 6) = "ERROR`t") {
        if (manual || !SyncErrShown)             ; 1분마다 같은 오류로 귀찮게 하지 않는다
            TrayTip(SubStr(txt, 7), "Claude 글 받기 실패")
        SyncErrShown := true
        return
    }
    SyncErrShown := false
    if (txt = "") {
        if manual
            TrayTip("새로 올라온 글이 없습니다", "네이버포스팅")
        return
    }
    files := StrSplit(txt, "`n", "`r")
    OnNewPost(files[files.Length], files.Length)   ; 마지막 줄이 가장 최근 글
}

; 새 글을 옵시디언에서 열고, 다음 F9/F10 대상으로 잡은 뒤 글쓰기 창을 열지 묻는다.
OnNewPost(f, count) {
    global CurFile, Pinned, WRITE_URL
    Pinned  := false                             ; 최신 글 추적 = 방금 받은 글
    CurFile := f
    name := RegExReplace(f, ".*\\")
    A_IconTip := "네이버포스팅(최신): " name
    try Run("obsidian://open?path=" UriEncode(f))
    catch
        try Run(f)
    ans := MsgBox("Claude 가 쓴 글이 옵시디언에 저장됐습니다"
        . (count > 1 ? " (" count "개 중 최신)" : "") ".`n`n  " name "`n`n"
        . "네이버 블로그 글쓰기 창을 열까요?`n"
        . "열리면 제목칸 클릭 → F9,  본문 클릭 → F10", "네이버포스팅", "YesNo Iconi T120")
    if (ans = "Yes")
        Run(WRITE_URL)
}

UriEncode(s) {
    buf := Buffer(StrPut(s, "UTF-8"))
    StrPut(s, buf, "UTF-8")
    out := ""
    Loop buf.Size - 1 {
        b := NumGet(buf, A_Index - 1, "UChar")
        if (b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A)
            || b = 0x2D || b = 0x2E || b = 0x5F || b = 0x7E
            out .= Chr(b)
        else
            out .= Format("%{:02X}", b)
    }
    return out
}

; ---------- 실제 타이핑 ----------

; 타이핑하는 동안 글 받기가 끼어들지 않게 표시해 둔다
RunTyping(part, label) {
    global Typing
    Typing := true
    try TypeOut(part, label)
    finally Typing := false
}

TypeOut(part, label) {
    global CHAR_MIN, CHAR_MAX, SENT_PAUSE, COMMA_PAUSE, LINE_PAUSE, THINK_ODDS, CurFile, Resume
    target := WinExist("A")

    ToolTip(label " 준비 중...")

    if !LoadClip(part, label) {
        ToolTip()
        return
    }
    txt := Trim(StrReplace(A_Clipboard, "`r"), " `t`n")     ; 평문. 앞뒤 빈 줄은 버린다
    if (txt = "") {
        ToolTip()
        MsgBox("입력할 내용이 비어 있습니다: " label)
        return
    }
    totalChars := StrLen(txt)

    ToolTip()
    pos := AskResume(part, label, txt)     ; 0 = 처음부터, -1 = 그만
    if (pos < 0)
        return

    ; 변환 중이나 물어보는 동안 포커스가 튀었으면 원래 창으로 되돌린다
    if (target && !WinActive(target)) {
        WinActivate(target)
        if !WinWaitActive(target, , 2) {
            MsgBox("대상 창이 바뀌었습니다. 입력할 자리를 다시 클릭하고 실행하세요.")
            return
        }
    }
    Sleep(150)

    est := Round((totalChars - pos) * (CHAR_MIN + CHAR_MAX) / 2 / 1000 / 60, 1)
    ToolTip(label (pos ? " 이어서 타이핑 (" Pct(pos, totalChars) "%부터)" : " 타이핑 시작")
          . "   [" RegExReplace(CurFile, ".*\\") "]`n"
          . "약 " est "분 예상 — 글이 다르면 Esc 누르고 F11 로 파일 변경")

    while (pos < totalChars) {
        ; 중단 장치 — 엉뚱한 곳에 계속 쏟아붓지 않도록 글자마다 확인하고, 멈춘 자리를 기억한다
        why := ""
        if GetKeyState("Esc", "P")
            why := label " 중단됨"
        else if (GetKeyState("LButton", "P") || GetKeyState("RButton", "P"))
            why := "클릭해서 " label " 중단"
        else if (target && !WinActive(target))
            why := "대상 창이 바뀌어 " label " 중단"
        if (why != "") {
            SaveResume(part, txt, pos)
            ToolTip(why " (" Pct(pos, totalChars) "%)`n"
                  . "커서를 글 끝에 두고 " (part = "title" ? "F9" : "F10") " 누르면 이어서 입력합니다")
            SetTimer(() => ToolTip(), -5000)
            return
        }

        ch := SubStr(txt, pos + 1, 1)
        if (ch = "`n") {
            Send("{Enter}")
            pos += 1
            ToolTip(label " 입력 중... " Pct(pos, totalChars) "%   (Esc 중단)")
            Sleep(LINE_PAUSE)
            continue
        }

        ; 이모지 같은 서로게이트 쌍은 반쪽만 보내면 깨지므로 두 단위를 한 글자로 본다
        n := 1
        if (Ord(ch) >= 0xD800 && Ord(ch) <= 0xDBFF) {
            ch := SubStr(txt, pos + 1, 2)
            n  := 2
        }
        SendText(ch)
        pos += n

        d := Random(CHAR_MIN, CHAR_MAX)
        if InStr(".!?", ch)
            d += SENT_PAUSE
        else if InStr(",", ch)
            d += COMMA_PAUSE
        if (THINK_ODDS > 0 && Random(1, THINK_ODDS) = 1)
            d += Random(300, 900)      ; 가끔 멈칫
        Sleep(d)
    }

    if Resume.Has(part)
        Resume.Delete(part)
    ToolTip()
    TrayTip(label " 타이핑 완료 (" totalChars "자)`n" RegExReplace(CurFile, ".*\\"), "네이버포스팅")
}

; 같은 글을 치다 멈춘 적이 있으면 어디서부터 칠지 묻는다. 시작 위치(0 = 처음부터), 그만이면 -1.
AskResume(part, label, txt) {
    global Resume, CurFile
    if !Resume.Has(part)
        return 0
    r := Resume[part]
    if (r.file != CurFile || r.pos <= 0)
        return 0
    pos := r.pos
    ; 멈춘 뒤 글을 고쳤으면 글자 수가 달라지므로, 마지막으로 친 글자들을 찾아 자리를 다시 잡는다
    k := StrLen(r.ctx)
    if (SubStr(txt, pos - k + 1, k) != r.ctx) {
        at := InStr(txt, r.ctx)
        pos := at ? at + k - 1 : 0
    }
    if (pos <= 0 || pos >= StrLen(txt))
        return 0

    ans := MsgBox(label "을(를) " Pct(pos, StrLen(txt)) "%까지 치다 멈췄습니다.`n`n"
        . "▶ 마지막으로 입력된 부분`n…" Vis(SubStr(txt, Max(1, pos - 29), Min(pos, 30))) "`n`n"
        . "▶ 이어서 입력할 부분`n" Vis(SubStr(txt, pos + 1, 30)) "…`n`n"
        . "커서가 '마지막으로 입력된 부분' 바로 뒤에 있어야 합니다.`n"
        . "(그 뒤에 잘못 들어간 글자가 있으면 먼저 지우세요)`n`n"
        . "예 = 이어서 입력`n아니요 = 처음부터 다시`n취소 = 그만", "네이버포스팅", "YesNoCancel Icon?")
    if (ans = "Cancel")
        return -1
    if (ans = "No") {
        Resume.Delete(part)
        return 0
    }
    return pos
}

SaveResume(part, txt, pos) {
    global Resume, CurFile, RESUME_CTX
    k := Min(pos, RESUME_CTX)
    Resume[part] := {file: CurFile, pos: pos, ctx: SubStr(txt, pos - k + 1, k)}
}

Pct(a, b) => Round(a / b * 100)
Vis(s) => StrReplace(s, "`n", "⏎")

; ---------- 붙여넣기 (서식 유지 폴백) ----------

PasteHere(part, label) {
    target := WinExist("A")
    ToolTip(label " 변환 중...")
    if !LoadClip(part, label) {
        ToolTip()
        return
    }
    if (target && !WinActive(target)) {
        WinActivate(target)
        WinWaitActive(target, , 2)
    }
    Sleep(120)
    Send("^v")
    ToolTip()
    TrayTip(label " 붙여넣기 완료", "네이버포스팅")
}

CopyOnly(part, label) {
    if LoadClip(part, label)
        TrayTip(label " 복사 완료 - 필요한 곳에서 Ctrl+V", "네이버포스팅")
}

; ---------- 단축키 ----------
; F9~F11 을 전역으로 잡으면 다른 앱의 기능키를 뺏으므로 브라우저에서만 켠다.

InBrowser() {
    return WinActive("ahk_exe chrome.exe")  || WinActive("ahk_exe msedge.exe")
        || WinActive("ahk_exe whale.exe")   || WinActive("ahk_exe firefox.exe")
        || WinActive("ahk_exe brave.exe")
}

#HotIf InBrowser()
F9::  RunTyping("title", "제목")
F10:: RunTyping("body",  "본문")
F11:: PickFile()
#HotIf

^!1:: PasteHere("title", "제목")
^!2:: PasteHere("body",  "본문")
^!3:: CopyOnly("tags",  "태그")
^!0:: PickFile()
^!9:: Unpin()
^!s:: SyncPosts(true)
^!q:: ExitApp()
