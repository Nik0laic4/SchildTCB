#!/usr/bin/env bash
# Schild TCB — прошивка bare-metal образа на USB-флешку и снятие boot-лога с NVMe.
#
# Зачем этот скрипт: прошивка и чтение NVMe требуют root, при этом ошибиться
# с выбором устройства очень дорого (можно перезаписать системный диск).
# Поэтому выбор целевого диска делается автоматически и строго:
#   1) только блочные устройства (не разделы) — lsblk -d;
#   2) только с транспортом "usb" (отсекает nvme/sata/mmc);
#   3) только с моделью, содержащей "SanDisk" (наша флешка).
#
# Лог загрузки Schild OS пишется во ВНУТРЕННИЙ NVMe (не во флешку):
# runtime_stubs.c (кольцо schild_log_buf, 8 КБ) -> Flush_Log_To_Nvme -> LBA 2000..2015.
#
# Использование (требует root):
#   sudo bash tools/flash_verify.sh status       # dry-run: показать флешку/NVMe/образ
#   sudo bash tools/flash_verify.sh flash        # записать schild_os.iso на флешку
#   sudo bash tools/flash_verify.sh capture-log  # снять boot-лог с NVMe
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ISO="$REPO_ROOT/src/schild_core/schild_os.iso"

# Переопределяемые переменные окружения (для нестандартных раскладок).
NVME="${SCHILD_NVME:-/dev/nvme0n1}"
LOG_START_LBA="${SCHILD_LOG_LBA:-2000}"
LOG_LBA_COUNT="${SCHILD_LOG_LBAS:-16}"
ISO_OVERWRITE="${SCHILD_ISO:-$ISO}"

usage() {
  cat <<'EOF'
Schild TCB — прошивка образа и снятие boot-лога с NVMe.

Использование: sudo bash tools/flash_verify.sh <команда>

Команды:
  status       Показать флешку/NVMe/образ без записи (dry-run).
  flash        Найти флешку SanDisk и записать на неё schild_os.iso.
  capture-log  Снять boot-лог Schild OS с внутреннего NVMe (LBA 2000..2015).

Переменные окружения (необязательно):
  SCHILD_NVME=/dev/nvme0n1    — устройство NVMe с логом
  SCHILD_LOG_LBA=2000         — стартовый LBA лога
  SCHILD_LOG_LBAS=16          — число LBA (16 x 512 = 8192 байт)
  SCHILD_ISO=/path/to.iso     — переопределить путь к образу
EOF
}

find_usb_sandisk() {
  # Печатает путь к первому USB-диску SanDisk (без разделов).
  local name tran model
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    tran="$(lsblk -nd -o TRAN "/dev/$name" 2>/dev/null | tr -d '[:space:]')"
    model="$(lsblk -nd -o MODEL "/dev/$name" 2>/dev/null | tr -d '[:space:]')"
    if [ "$tran" = "usb" ] && printf '%s' "$model" | grep -q 'SanDisk'; then
      printf '%s\n' "/dev/$name"
      return 0
    fi
  done < <(lsblk -o NAME -nrd 2>/dev/null)
  return 1
}

cmd_status() {
  echo "== Schild TCB: status (dry-run) =="
  echo
  if [ -f "$ISO_OVERWRITE" ]; then
    stat -c 'Образ:   %n (%s байт, собран %y)' "$ISO_OVERWRITE"
  else
    echo "Образ:   НЕ НАЙДЕН: $ISO_OVERWRITE" >&2
  fi
  if usb="$(find_usb_sandisk)"; then
    local sz
    sz="$(lsblk -nd -o SIZE "$usb" | tr -d '[:space:]')"
    echo "Флешка:  $usb ($sz, SanDisk USB) — цель прошивки"
  else
    echo "Флешка:  НЕ НАЙДЕНА (нет USB-устройства SanDisk)" >&2
  fi
  if [ -b "$NVME" ]; then
    local nsz
    nsz="$(lsblk -nd -o SIZE "$NVME" | tr -d '[:space:]')"
    echo "NVMe:    $NVME ($nsz) — источник лога (LBA $LOG_START_LBA..$((LOG_START_LBA+LOG_LBA_COUNT-1)))"
  else
    echo "NVMe:    $NVME не найден" >&2
  fi
}

cmd_flash() {
  local usb
  echo "== Schild TCB: flash =="
  [ -f "$ISO_OVERWRITE" ] || { echo "Ошибка: образ не найден: $ISO_OVERWRITE" >&2; exit 1; }
  usb="$(find_usb_sandisk)" || { echo "Ошибка: USB-флешка SanDisk не найдена. Прерываю (безопасность)." >&2; exit 1; }

  local sz
  sz="$(lsblk -nd -o SIZE "$usb" | tr -d '[:space:]')"
  echo "Цель:    $usb ($sz)"
  echo "Образ:   $ISO_OVERWRITE"
  echo
  echo "ВНИМАНИЕ: всё содержимое $usb будет УНИЧТОЖЕНО."
  read -r -p "Продолжить? [y/N] " ans
  case "$ans" in
    y|Y|yes|YES|д|Д|да|ДА) ;;
    *) echo "Отменено."; exit 1 ;;
  esac

  echo "Записываю образ на $usb ..."
  dd if="$ISO_OVERWRITE" of="$usb" bs=4M oflag=sync status=progress
  sync
  echo "Готово. Образ записан на $usb."
  echo "Следующий шаг: загрузите T580 с этой флешки, дайте Schild OS выйти"
  echo "в сеть (:80), затем выключите и вернитесь в Linux — и выполните:"
  echo "  sudo bash tools/flash_verify.sh capture-log"
}

cmd_capture_log() {
  echo "== Schild TCB: capture-log (NVMe LBA $LOG_START_LBA..$((LOG_START_LBA+LOG_LBA_COUNT-1))) =="
  [ -b "$NVME" ] || { echo "Ошибка: $NVME не найден" >&2; exit 1; }

  local raw="/tmp/schild_log.raw"
  dd if="$NVME" of="$raw" bs=512 skip="$LOG_START_LBA" count="$LOG_LBA_COUNT" status=none

  local nz
  nz="$(tr -d '\0' < "$raw" | wc -c)"
  echo "Сырой дамп: $raw ($((LOG_LBA_COUNT*512)) байт, непустых символов: $nz)"
  echo "--- лог (нули удалены) ---"
  tr -d '\0' < "$raw"
  echo "--- конец лога ---"
}

case "${1:-}" in
  status)       cmd_status ;;
  flash)        cmd_flash ;;
  capture-log)  cmd_capture_log ;;
  help|-h|--help|"") usage ;;
  *) echo "Неизвестная команда: ${1:-}" >&2; usage >&2; exit 1 ;;
esac
