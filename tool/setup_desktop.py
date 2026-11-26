"""Ajusta las carpetas de Windows y Linux que crea `flutter create`:
nombre "Kumo" en la ventana, ícono del gatito y tamaño de ventana cómodo."""
import shutil
from pathlib import Path

HERE = Path(__file__).parent / "desktop"


def sub(path: Path, old: str, new: str) -> None:
    if not path.exists():
        return
    s = path.read_text(encoding="utf-8")
    path.write_text(s.replace(old, new), encoding="utf-8")


# ---------------------------------------------------------------- Linux
cc = Path("linux/runner/my_application.cc")
if not cc.exists():
    cc = Path("linux/my_application.cc")
sub(cc, '"app_notas"', '"Kumo"')
sub(cc, "gtk_window_set_default_size(window, 1280, 720);", "gtk_window_set_default_size(window, 1200, 860);")
if cc.exists() and "gtk_window_set_icon_from_file" not in cc.read_text(encoding="utf-8"):
    sub(
        cc,
        "gtk_window_set_default_size(window, 1200, 860);",
        "gtk_window_set_default_size(window, 1200, 860);\n"
        '  { g_autofree gchar* exe = g_file_read_link("/proc/self/exe", nullptr);\n'
        "    g_autofree gchar* dir = exe ? g_path_get_dirname(exe) : nullptr;\n"
        '    g_autofree gchar* icon = dir ? g_build_filename(dir, "kumo.png", nullptr) : nullptr;\n'
        "    if (icon) gtk_window_set_icon_from_file(window, icon, nullptr); }",
    )
for cm in [Path("linux/CMakeLists.txt")]:
    sub(cm, 'set(BINARY_NAME "app_notas")', 'set(BINARY_NAME "kumo")')

# -------------------------------------------------------------- Windows
main = Path("windows/runner/main.cpp")
sub(main, 'L"app_notas"', 'L"Kumo"')
sub(main, "Win32Window::Size size(1280, 720);", "Win32Window::Size size(1200, 860);")
rc = Path("windows/runner/Runner.rc")
for k in ["FileDescription", "InternalName", "ProductName"]:
    sub(rc, f'VALUE "{k}", "app_notas"', f'VALUE "{k}", "Kumo"')
sub(rc, 'VALUE "OriginalFilename", "app_notas.exe"', 'VALUE "OriginalFilename", "Kumo.exe"')
sub(Path("windows/CMakeLists.txt"), 'set(BINARY_NAME "app_notas")', 'set(BINARY_NAME "Kumo")')
ico = Path("windows/runner/resources/app_icon.ico")
if ico.parent.exists():
    shutil.copy(HERE / "app_icon.ico", ico)

print("Escritorio listo")
