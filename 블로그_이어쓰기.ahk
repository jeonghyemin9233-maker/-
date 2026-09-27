#Requires AutoHotkey v2.0
#SingleInstance Force

; 블로그 원고 이어쓰기
;   F7       타이핑 시작 / 멈춘 곳부터 이어서
;   F8       멈춤 (어디까지 쳤는지 저장) — 타이핑 중일 때만 작동
;   Ctrl+F7  다른 원고 고르기
; 타이핑 중에 다른 창으로 넘어가면 저절로 멈추고 위치를 저장한다.
; 기존 F9/F10/F11 스크립트와 같이 켜 둬도 된다 (키가 겹치지 않음).

CharDelay := 15                                   ; 글자 사이 간격(ms). 글자가 빠지면 30~50으로 늘린다
SaveFile  := A_ScriptDir "\이어쓰기_진행.ini"     ; 원고 경로와 입력한 글자 수를 여기에 저장
Typing    := false
StopFlag  := false

F7:: StartOrResume()

^F7:: {
    if Typing
        return
    path := PickFile()
    if (path != "") {
        SaveProgress(path, 0)
        StartOrResume()
    }
}

#HotIf Typing
F8:: StopTyping()
#HotIf

StartOrResume() {
    global Typing, StopFlag
    if Typing
        return
    path := IniRead(SaveFile, "진행", "파일", "")
    pos  := Integer(IniRead(SaveFile, "진행", "위치", "0"))
    if (path = "" || !FileExist(path)) {
        path := PickFile()
        if (path = "")
            return
        pos := 0
    }
    text  := LoadText(path)
    total := StrLen(text)
    SplitPath(path, &name)

    if (pos >= total) {
        if MsgBox("「" name "」은(는) 끝까지 입력했습니다.`n처음부터 다시 입력할까요?`n`n(다른 원고는 Ctrl+F7)", "이어쓰기", "YesNo Icon?") != "Yes"
            return
        pos := 0
    } else if (pos > 0) {
        r := MsgBox("「" name "」을(를) " pos " / " total "자까지 입력하다 멈췄습니다.`n`n"
            . "▶ 마지막으로 입력된 부분`n…" Visible(SubStr(text, Max(1, pos - 29), Min(pos, 30))) "`n`n"
            . "▶ 이어서 입력할 부분`n" Visible(SubStr(text, pos + 1, 30)) "…`n`n"
            . "블로그에서 커서를 '마지막으로 입력된 부분' 바로 뒤에 두세요.`n`n"
            . "예 = 이어서 입력    아니요 = 처음부터    취소 = 그만", "이어쓰기", "YesNoCancel Icon?")
        if (r = "Cancel")
            return
        if (r = "No")
            pos := 0
    }
    SaveProgress(path, pos)

    Typing := true, StopFlag := false
    Loop 3 {
        ToolTip("입력할 곳을 클릭해 두세요 — " (4 - A_Index) "초 뒤 시작 (F8: 취소)")
        Sleep(1000)
        if StopFlag
            break
    }
    hwnd := WinExist("A")                         ; 이 창에만 입력한다
    i := pos, count := 0, reason := ""
    while (i < total) {
        if StopFlag {
            reason := "F8로 멈췄습니다."
            break
        }
        if !WinActive("ahk_id " hwnd) {
            reason := "다른 창으로 넘어가서 멈췄습니다."
            break
        }
        n := 1                                    ; 이모지 같은 두 칸짜리 글자는 한 번에 보낸다
        c := Ord(SubStr(text, i + 1, 1))
        if (c >= 0xD800 && c <= 0xDBFF)
            n := 2
        ch := SubStr(text, i + 1, n)
        if (ch = "`n")
            Send("{Enter}")
        else
            SendText(ch)
        i += n
        if (Mod(++count, 10) = 0) {
            SaveProgress(path, i)
            ToolTip("입력 중 " i " / " total "자  (F8: 멈춤)")
        }
        Sleep(CharDelay)
    }
    SaveProgress(path, i)
    Typing := false
    if (i >= total)
        Notice("「" name "」 끝까지 입력했습니다.")
    else
        Notice(reason " " i " / " total "자 — F7을 누르면 여기서부터 이어서 입력합니다.")
}

StopTyping() {
    global StopFlag
    StopFlag := true
}

PickFile() {
    last := IniRead(SaveFile, "진행", "파일", "")
    dir := ""
    if (last != "")
        SplitPath(last, , &dir)
    return FileSelect(1, dir, "타이핑할 원고 고르기", "원고 (*.txt; *.md)")
}

LoadText(path) {
    t := FileRead(path, "UTF-8")
    t := StrReplace(t, "`r`n", "`n")
    return StrReplace(t, "`r", "`n")
}

SaveProgress(path, pos) {
    IniWrite(path, SaveFile, "진행", "파일")
    IniWrite(pos, SaveFile, "진행", "위치")
}

Visible(s) => StrReplace(s, "`n", "⏎")

Notice(msg) {
    ToolTip(msg)
    SetTimer(() => ToolTip(), -6000)
}
