// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint contributors

struct DisplayWindowMemoryStrings {
    let section: String
    let rememberSize: String
    let rememberSizeCaption: String
    let restoreLayout: String
    let restoreLayoutCaption: String

    static func localized(_ language: AppLanguage) -> Self {
        switch language {
        case .enUS: return .init(section: "Display memory", rememberSize: "Remember window size per display", rememberSizeCaption: "Restore a window’s learned size when it first appears on another display.", restoreLayout: "Restore layout when a display reconnects", restoreLayoutCaption: "After reconnection, move and resize windows that are still open to their last positions on that display.")
        case .zhTW: return .init(section: "螢幕視窗記憶", rememberSize: "依螢幕記住視窗大小", rememberSizeCaption: "視窗首次出現在另一個螢幕時，套用先前記住的大小。", restoreLayout: "螢幕重新連接時還原佈局", restoreLayoutCaption: "重新連接後，將仍開啟的視窗移回該螢幕上次的位置並調整大小。")
        case .zhHK: return .init(section: "螢幕視窗記憶", rememberSize: "按螢幕記住視窗大小", rememberSizeCaption: "視窗首次出現在另一個螢幕時，套用之前記住的大小。", restoreLayout: "螢幕重新連接時還原佈局", restoreLayoutCaption: "重新連接後，將仍開啟的視窗移回該螢幕上次的位置並調整大小。")
        case .zhHans: return .init(section: "显示器窗口记忆", rememberSize: "按显示器记住窗口大小", rememberSizeCaption: "窗口首次出现在另一台显示器时，应用之前记住的大小。", restoreLayout: "显示器重新连接时恢复布局", restoreLayoutCaption: "重新连接后，将仍打开的窗口移回该显示器上次的位置并调整大小。")
        case .ja: return .init(section: "ディスプレイのウインドウ記憶", rememberSize: "ディスプレイごとにウインドウサイズを記憶", rememberSizeCaption: "別のディスプレイに初めて現れたとき、記憶したサイズに戻します。", restoreLayout: "ディスプレイの再接続時に配置を復元", restoreLayoutCaption: "再接続後、開いているウインドウをそのディスプレイの最後の位置とサイズに戻します。")
        case .ko: return .init(section: "디스플레이 창 기억", rememberSize: "디스플레이별 창 크기 기억", rememberSizeCaption: "창이 다른 디스플레이에 처음 나타나면 기억한 크기를 적용합니다.", restoreLayout: "디스플레이 재연결 시 배치 복원", restoreLayoutCaption: "재연결 후 열려 있는 창을 해당 디스플레이의 마지막 위치와 크기로 복원합니다.")
        case .ptBR: return .init(section: "Memória das telas", rememberSize: "Lembrar o tamanho das janelas por tela", rememberSizeCaption: "Aplica o tamanho lembrado quando uma janela aparece em outra tela.", restoreLayout: "Restaurar a disposição ao reconectar uma tela", restoreLayoutCaption: "Move e redimensiona as janelas ainda abertas para suas últimas posições nessa tela.")
        case .tr: return .init(section: "Ekran belleği", rememberSize: "Pencere boyutunu ekrana göre hatırla", rememberSizeCaption: "Pencere başka bir ekranda ilk kez göründüğünde kayıtlı boyutunu uygular.", restoreLayout: "Ekran yeniden bağlandığında düzeni geri yükle", restoreLayoutCaption: "Açık pencereleri o ekrandaki son konumlarına ve boyutlarına döndürür.")
        case .ru: return .init(section: "Память экранов", rememberSize: "Запоминать размер окна для каждого экрана", rememberSizeCaption: "Применяет сохранённый размер при первом появлении окна на другом экране.", restoreLayout: "Восстанавливать расположение при подключении экрана", restoreLayoutCaption: "Возвращает открытые окна на их последние места и размеры на этом экране.")
        case .es: return .init(section: "Memoria de pantallas", rememberSize: "Recordar el tamaño de las ventanas por pantalla", rememberSizeCaption: "Aplica el tamaño guardado cuando una ventana aparece en otra pantalla.", restoreLayout: "Restaurar la disposición al reconectar una pantalla", restoreLayoutCaption: "Mueve y ajusta las ventanas abiertas a su última posición y tamaño en esa pantalla.")
        case .sk: return .init(section: "Pamäť obrazoviek", rememberSize: "Pamätať veľkosť okien pre každú obrazovku", rememberSizeCaption: "Pri prvom zobrazení okna na inej obrazovke použije uloženú veľkosť.", restoreLayout: "Obnoviť rozloženie po opätovnom pripojení obrazovky", restoreLayoutCaption: "Otvorené okná vráti na posledné pozície a veľkosti na tejto obrazovke.")
        case .de: return .init(section: "Bildschirmspeicher", rememberSize: "Fenstergröße je Bildschirm merken", rememberSizeCaption: "Wendet die gemerkte Größe an, wenn ein Fenster erstmals auf einem anderen Bildschirm erscheint.", restoreLayout: "Anordnung bei erneutem Anschluss wiederherstellen", restoreLayoutCaption: "Verschiebt und skaliert noch offene Fenster auf ihre letzten Positionen auf diesem Bildschirm.")
        case .fr: return .init(section: "Mémoire des écrans", rememberSize: "Mémoriser la taille des fenêtres par écran", rememberSizeCaption: "Applique la taille mémorisée lorsqu’une fenêtre apparaît sur un autre écran.", restoreLayout: "Restaurer la disposition à la reconnexion d’un écran", restoreLayoutCaption: "Replace et redimensionne les fenêtres encore ouvertes selon leur dernière disposition sur cet écran.")
        case .it: return .init(section: "Memoria degli schermi", rememberSize: "Ricorda la dimensione delle finestre per schermo", rememberSizeCaption: "Applica la dimensione salvata quando una finestra appare su un altro schermo.", restoreLayout: "Ripristina la disposizione alla riconnessione", restoreLayoutCaption: "Sposta e ridimensiona le finestre ancora aperte nelle ultime posizioni su quello schermo.")
        case .uk: return .init(section: "Пам’ять екранів", rememberSize: "Запам’ятовувати розмір вікон для кожного екрана", rememberSizeCaption: "Застосовує збережений розмір, коли вікно вперше з’являється на іншому екрані.", restoreLayout: "Відновлювати розташування після підключення екрана", restoreLayoutCaption: "Повертає відкриті вікна на їхні останні місця та розміри на цьому екрані.")
        }
    }
}
