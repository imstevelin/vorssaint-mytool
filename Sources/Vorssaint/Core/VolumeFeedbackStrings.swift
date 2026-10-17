// SPDX-License-Identifier: GPL-3.0-or-later
struct VolumeFeedbackStrings {
    let title: String
    let caption: String
    static func localized(_ language: AppLanguage) -> Self {
        switch language {
        case .enUS: return .init(title: "Play feedback when changing volume", caption: "Play the system volume sound through the current output after adjustments in this tool.")
        case .zhTW: return .init(title: "調整音量時播放回饋音", caption: "使用本工具調整整體音量後，從目前的音訊輸出播放系統音量提示音。")
        case .zhHK: return .init(title: "調整音量時播放回饋音", caption: "使用本工具調整整體音量後，從目前的音訊輸出播放系統音量提示音。")
        case .zhHans: return .init(title: "调整音量时播放反馈音", caption: "使用本工具调整整体音量后，从当前音频输出播放系统音量提示音。")
        case .ja: return .init(title: "音量変更時に操作音を再生", caption: "このツールで音量を変更した後、現在の出力からシステムの音量操作音を再生します。")
        case .ko: return .init(title: "음량 변경 시 피드백 사운드 재생", caption: "이 도구로 전체 음량을 조절하면 현재 출력으로 시스템 음량 사운드를 재생합니다.")
        case .ptBR: return .init(title: "Reproduzir som ao alterar o volume", caption: "Reproduz o som de volume do sistema na saída atual após ajustes nesta ferramenta.")
        case .tr: return .init(title: "Ses düzeyi değiştiğinde geri bildirim çal", caption: "Bu araçta ses düzeyi ayarlandıktan sonra mevcut çıkıştan sistem sesini çalar.")
        case .ru: return .init(title: "Звук при изменении громкости", caption: "Воспроизводит системный звук громкости через текущий выход после настройки в этой утилите.")
        case .es: return .init(title: "Reproducir sonido al cambiar el volumen", caption: "Reproduce el sonido de volumen del sistema por la salida actual tras los ajustes en esta herramienta.")
        case .sk: return .init(title: "Prehrať zvuk pri zmene hlasitosti", caption: "Po úprave hlasitosti v tomto nástroji prehrá systémový zvuk cez aktuálny výstup.")
        case .de: return .init(title: "Ton beim Ändern der Lautstärke abspielen", caption: "Spielt nach Lautstärkeänderungen in diesem Tool den Systemton über die aktuelle Ausgabe ab.")
        case .fr: return .init(title: "Émettre un son au changement de volume", caption: "Joue le son de volume du système via la sortie actuelle après un réglage dans cet outil.")
        case .it: return .init(title: "Riproduci un suono quando cambia il volume", caption: "Riproduce il suono del volume di sistema tramite l’uscita attuale dopo le regolazioni in questo strumento.")
        case .uk: return .init(title: "Звук під час зміни гучності", caption: "Відтворює системний звук гучності через поточний вихід після налаштування в цій утиліті.")
        }
    }
}
