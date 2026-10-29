#!/usr/bin/env bash

# Colour helper (shadows `tput` for the calls below). Some consoles/SSH clients
# report TERM=vt102/vt220, whose terminfo has no colours, so real tput prints
# nothing - yet they render ANSI colours fine. Fall back to raw ANSI codes then,
# and downgrade 256-colour indexes on 8/16-colour terminals (TERM=linux turns
# `setaf 214` into a broken sequence). Whether colours are used at all is
# decided by _XT_COLOR (set from --color / NO_COLOR / TERM / tty check below).
_XT_NCOLORS=$(command tput colors 2>/dev/null) || _XT_NCOLORS=-1
[[ "$_XT_NCOLORS" =~ ^[0-9]+$ ]] || _XT_NCOLORS=-1
tput() {
  if [[ "${_XT_COLOR:-0}" != 1 ]]; then return 0; fi
  case "$1" in
    setaf)
      local n=$2   # optional $3: colour to use on 8/16-colour terminals (default yellow)
      if (( n > 15 && _XT_NCOLORS < 256 )); then n=${3:-3}; fi   # e.g. orange -> yellow
      # Only ask terminfo for colours it has (TERM=linux has 8, so setaf 15 breaks).
      if (( _XT_NCOLORS >= 8 && n < _XT_NCOLORS )); then command tput setaf "$n" 2>/dev/null && return 0; fi
      if (( n < 8 )); then printf '\033[3%dm' "$n"
      elif (( n < 16 )); then printf '\033[9%dm' $((n - 8))
      else printf '\033[38;5;%dm' "$n"; fi ;;
    bold) printf '\033[1m' ;;
    sgr0) printf '\033[0m' ;;
    *)    command tput "$@" 2>/dev/null ;;
  esac
}

# Function to set color scheme
set_color_scheme() {
  local scheme=$1
  if [ "$scheme" == "alternative" ]; then
    COLOR_PERMISSIONS=$(tput setaf 4) # Blue
    COLOR_SIZE=$(tput setaf 2) # Green
    COLOR_DIRECTORY=$(tput setaf 1) # Red
    COLOR_BOLD_DIRECTORY=$(tput bold; tput setaf 1) # Bold Red
    COLOR_OWNER_GROUP=$(tput setaf 3) # Yellow
    COLOR_MODIFIED=$(tput setaf 6) # Cyan
    COLOR_FILE=$(tput setaf 5) # Magenta
    COLOR_BOLD_FILE=$(tput bold; tput setaf 5) # Bold Magenta
  elif [ "$scheme" == "christmas" ]; then
    COLOR_PERMISSIONS=$(tput setaf 2) # Green
    COLOR_SIZE=$(tput setaf 1) # Red
    COLOR_DIRECTORY=$(tput setaf 2) # Green
    COLOR_BOLD_DIRECTORY=$(tput bold; tput setaf 2) # Bold Green
    COLOR_OWNER_GROUP=$(tput setaf 1) # Red
    COLOR_MODIFIED=$(tput setaf 7) # White
    COLOR_FILE=$(tput setaf 1) # Red
    COLOR_BOLD_FILE=$(tput bold; tput setaf 1) # Bold Red
  elif [ "$scheme" == "halloween" ]; then
    COLOR_PERMISSIONS=$(tput setaf 3) # Yellow
    COLOR_SIZE=$(tput setaf 1) # Red
    COLOR_DIRECTORY=$(tput setaf 214) # Orange
    COLOR_BOLD_DIRECTORY=$(tput bold; tput setaf 214) # Bold Orange
    COLOR_OWNER_GROUP=$(tput setaf 1) # Red
    COLOR_MODIFIED=$(tput setaf 3) # Yellow
    COLOR_FILE=$(tput setaf 1) # Red
    COLOR_BOLD_FILE=$(tput bold; tput setaf 1) # Bold Red
    COLOR_WHITE=$(tput setaf 7) # White
  elif [ "$scheme" == "ghost" ]; then
    COLOR_PERMISSIONS=$(tput setaf 8) # Grey
    COLOR_SIZE=$(tput setaf 30 6) # Dark Teal (plain cyan on 8/16-colour terminals)
    COLOR_DIRECTORY=$(tput setaf 15) # Bright White
    COLOR_BOLD_DIRECTORY=$(tput bold; tput setaf 15) # Bold Bright White
    COLOR_OWNER_GROUP=$(tput setaf 8) # Grey
    COLOR_MODIFIED=$(tput setaf 6) # Cyan
    COLOR_FILE=$(tput setaf 7) # White
    COLOR_BOLD_FILE=$(tput bold; tput setaf 7) # Bold White
    COLOR_WHITE=$(tput bold; tput setaf 15) # Bold Bright White
  else
    COLOR_PERMISSIONS=$(tput setaf 5) # Default Purple
    COLOR_SIZE=$(tput setaf 3) # Default Yellow
    COLOR_DIRECTORY=$(tput setaf 6) # Default Teal
    COLOR_BOLD_DIRECTORY=$(tput bold; tput setaf 6) # Bold Teal
    COLOR_OWNER_GROUP=$(tput setaf 2) # Default Green
    COLOR_MODIFIED=$(tput setaf 5) # Default Purple
    COLOR_FILE=$(tput setaf 2) # Default Green
    COLOR_BOLD_FILE=$(tput bold; tput setaf 2) # Bold Green
  fi
  COLOR_RESET=$(tput sgr0)
}

# Function to print ASCII art based on the color scheme
print_ascii_art() {
  local scheme=$1
  if [ "$scheme" == "christmas" ]; then
    echo -e "${COLOR_BOLD_DIRECTORY}  *  ${COLOR_RESET}"
    echo -e "${COLOR_BOLD_DIRECTORY} *** ${COLOR_RESET}"
    echo -e "${COLOR_BOLD_DIRECTORY}*****${COLOR_RESET}"
    echo -e "${COLOR_BOLD_DIRECTORY}  |  ${COLOR_RESET}"
  elif [ "$scheme" == "halloween" ]; then
    echo -e "${COLOR_WHITE}  _____  ${COLOR_RESET}"
    echo -e "${COLOR_WHITE} /     \\ ${COLOR_RESET}"
    echo -e "${COLOR_WHITE}|(0) (0)|${COLOR_RESET}"
    echo -e "${COLOR_WHITE} \\  ^  / ${COLOR_RESET}"
    echo -e "${COLOR_WHITE}  |||||  ${COLOR_RESET}"
    echo -e "${COLOR_WHITE}  |||||  ${COLOR_RESET}"
  elif [ "$scheme" == "ghost" ]; then
    echo -e "${COLOR_WHITE}  .-----.  ${COLOR_RESET}"
    echo -e "${COLOR_WHITE} / o   o \\ ${COLOR_RESET}"
    echo -e "${COLOR_WHITE}|    O    |${COLOR_RESET}"
    echo -e "${COLOR_WHITE}|         |${COLOR_RESET}"
    echo -e "${COLOR_WHITE} \\/\\/\\/\\/\\/ ${COLOR_RESET}"
  elif [ "$scheme" == "alternative" ]; then
    echo -e "${COLOR_BOLD_DIRECTORY}  /\\  ${COLOR_RESET}"
    echo -e "${COLOR_BOLD_DIRECTORY} /  \\ ${COLOR_RESET}"
    echo -e "${COLOR_BOLD_DIRECTORY}/____\\${COLOR_RESET}"
  else
    # Default scheme shows no ASCII art
    return
  fi
}

# Function to select a random theme
select_random_theme() {
  local themes=("default" "alternative" "christmas" "halloween" "ghost")
  local random_index=$((RANDOM % ${#themes[@]}))
  echo "${themes[$random_index]}"
}

# Configuration for column headers
HEADER_PERMISSIONS="Permissions"
HEADER_OWNER_GROUP="Owner::Group"
HEADER_SIZE="Size"
HEADER_USAGE="Usage"
HEADER_MODIFIED="Last Modified"
HEADER_GIT="Git"
HEADER_DIRECTORY="Name"
HEADER_ACL="ACL"

# Configuration for flag variables
FLAG_INCLUDE_FILES="f"
FLAG_MAX_DEPTH="L"
FLAG_SHOW_PERMISSIONS="p"
FLAG_SHOW_DATETIME="t"
FLAG_SHOW_USERGROUP="u"
FLAG_INCLUDE_HIDDEN="a"
FLAG_EXPORT_CSV="C"
FLAG_COLOR_SCHEME="s"
FLAG_RANDOM_THEME="r"
FLAG_SHOW_ACL="A"
FLAG_SORT="o"
FLAG_REVERSE="O"
FLAG_DIRS_FIRST="D"
FLAG_HEATMAP="H"
FLAG_GIT="g"

SEP=$'\x1f'   # separator for child lists (never appears in real file names)

# Per-entry data, keyed by path exactly as find prints it.
declare -A E_TYPE E_XTYPE E_MTIME E_DATE E_USER E_GROUP E_MODE E_BYTES E_PERMS
declare -A CHILDREN GIT_CODE GIT_DIRTY GIT_UNTRACKED
ALL_PATHS=()
GIT_ENABLED=false
GIT_ALL_UNTRACKED=false
COUNT_DIRS=0
COUNT_FILES=0

# Bytes -> the same text `du -h` prints (1024-based, rounded up, e.g. 4.0K, 12K).
human_size() {
  local b=$1 d=1 i tenths whole units="KMGTPE"
  if (( b < 1024 )); then REPLY=$b; return; fi
  for (( i = 0; i < ${#units}; i++ )); do
    d=$(( d * 1024 ))
    tenths=$(( (b * 10 + d - 1) / d ))
    if (( tenths < 100 )); then REPLY="$(( tenths / 10 )).$(( tenths % 10 ))${units:i:1}"; return; fi
    whole=$(( (b + d - 1) / d ))
    if (( whole < 1024 || i == ${#units} - 1 )); then REPLY="${whole}${units:i:1}"; return; fi
  done
}

parent_of() {
  REPLY=${1%/*}
  [ -n "$REPLY" ] || REPLY=/
}

csv_quote() {
  REPLY="\"${1//\"/\"\"}\""
}

# One pass of find (metadata) + one pass of du (directory totals) instead of
# ls/stat/du per entry. find does not follow symlinks, so linked directories
# are listed but not descended into (no loops).
collect_entries() {
  local root=$1 i n p line
  local fmt='%y\0%Y\0%T@\0%TY-%Tm-%Td %TH:%TM:%TS\0%u\0%g\0%M\0%b\0%p\0'
  local -a expr=() f=() d=() ls_out=()
  [ "$include_hidden" == true ] || expr+=( '(' -name '.*' -prune ')' -o )
  [ "$include_files" == true ] || expr+=( '(' ! -xtype d ')' -o )

  mapfile -d '' -t f < <(
    find "$root" -maxdepth 0 -printf "$fmt" 2>/dev/null
    if (( max_depth > 0 )); then
      find "$root" -mindepth 1 -maxdepth "$max_depth" "${expr[@]}" -printf "$fmt" 2>/dev/null
    fi
  )
  n=${#f[@]}
  for (( i = 0; i + 8 < n; i += 9 )); do
    p=${f[i+8]}
    E_TYPE[$p]=${f[i]}
    E_XTYPE[$p]=${f[i+1]}
    E_MTIME[$p]=${f[i+2]%.*}
    E_DATE[$p]=${f[i+3]%.*}
    E_USER[$p]=${f[i+4]}
    E_GROUP[$p]=${f[i+5]}
    E_MODE[$p]=${f[i+6]}
    E_BYTES[$p]=$(( ${f[i+7]:-0} * 512 ))   # disk usage of non-directories
    ALL_PATHS+=("$p")
  done

  # Directory totals (includes hidden content, like `du -sh` did before).
  mapfile -d '' -t d < <(du -B1 -d "$max_depth" -0 -- "$root" 2>/dev/null)
  for line in "${d[@]}"; do
    p=${line#*$'\t'}
    [ -n "${E_TYPE[$p]+x}" ] && E_BYTES[$p]=${line%%$'\t'*}
  done

  # Permissions as ls shows them (keeps the ACL "+" marker), one batched call.
  if [ "$show_permissions" == true ] || [ "$show_acl" == true ]; then
    mapfile -t ls_out < <(printf '%s\0' "${ALL_PATHS[@]}" | xargs -0 ls -dlUb -- 2>/dev/null)
    if (( ${#ls_out[@]} == ${#ALL_PATHS[@]} )); then
      for (( i = 0; i < ${#ALL_PATHS[@]}; i++ )); do E_PERMS[${ALL_PATHS[i]}]=${ls_out[i]%% *}; done
    else
      for p in "${ALL_PATHS[@]}"; do E_PERMS[$p]=${E_MODE[$p]}; done
    fi
  fi
}

# Map `git status` onto the listed paths. Directories that contain changes
# (at any depth) are flagged with "*".
collect_git() {
  local root=$1 root_abs top i code path abs mine q
  local -a g=()
  command -v git >/dev/null 2>&1 || return 0
  top=$(git -C "$root" rev-parse --show-toplevel 2>/dev/null) || return 0
  root_abs=$(cd "$root" 2>/dev/null && pwd -P) || return 0
  top=$(cd "$top" 2>/dev/null && pwd -P) || return 0
  GIT_ENABLED=true
  mapfile -d '' -t g < <(git -C "$top" status --porcelain=v1 -z --untracked-files=normal 2>/dev/null)
  for (( i = 0; i < ${#g[@]}; i++ )); do
    code=${g[i]:0:2}
    path=${g[i]:3}
    [[ ${code:0:1} == [RC] ]] && (( i++ ))   # skip the rename/copy source path
    abs="${top%/}/${path%/}"
    if [[ $code == '??' && $path == */ && ( $root_abs == "$abs" || $root_abs == "$abs"/* ) ]]; then
      GIT_ALL_UNTRACKED=true                  # the whole listed directory is untracked
      continue
    fi
    if [[ $abs == "$root_abs" ]]; then
      mine=$root
    elif [[ $abs == "${root_abs%/}"/* ]]; then
      mine=${abs#"${root_abs%/}"/}
      if [ "$root" == / ]; then mine="/$mine"; else mine="$root/$mine"; fi
    else
      continue
    fi
    if [[ $code == '??' && $path == */ ]]; then
      GIT_UNTRACKED[$mine]=1
    fi
    GIT_CODE[$mine]=$code
    q=$mine
    while [[ $q != "$root" && $q == */* ]]; do
      parent_of "$q"; q=$REPLY
      [ -n "${GIT_DIRTY[$q]+x}" ] && break
      GIT_DIRTY[$q]=1
    done
  done
}

git_code_for() {
  local p=$1 q
  if [ -n "${GIT_CODE[$p]+x}" ]; then REPLY=${GIT_CODE[$p]}; return; fi
  if [ "$GIT_ALL_UNTRACKED" == true ]; then REPLY='??'; return; fi
  if (( ${#GIT_UNTRACKED[@]} > 0 )); then
    q=$p
    while [[ $q != "$root" && $q == */* ]]; do
      parent_of "$q"; q=$REPLY
      if [ -n "${GIT_UNTRACKED[$q]+x}" ]; then REPLY='??'; return; fi
    done
  fi
  if [ -n "${GIT_DIRTY[$p]+x}" ]; then REPLY='*'; else REPLY=''; fi
}

# Sort every entry once and append it to its parent's child list in order.
build_children() {
  local i p name grp num ext dflag line t
  # shellcheck disable=SC2054  # commas are sort key ranges, not separators
  local -a order=() sort_args=(-z -t $'\t' -k1,1n)
  local rev=""
  [ "$sort_reverse" == true ] && rev=r
  # shellcheck disable=SC2054
  case $sort_key in
    name) sort_args+=(-k2,2n"$rev" "-k6$rev") ;;
    size) if [ -n "$rev" ]; then sort_args+=(-k3,3n); else sort_args+=(-k3,3nr); fi; sort_args+=(-k6) ;;
    time) if [ -n "$rev" ]; then sort_args+=(-k3,3n); else sort_args+=(-k3,3nr); fi; sort_args+=(-k6) ;;
    type) sort_args+=(-k4,4"$rev" -k6) ;;
    none) sort_args+=(-s) ;;
  esac
  mapfile -d '' -t order < <(
    for (( i = 1; i < ${#ALL_PATHS[@]}; i++ )); do
      p=${ALL_PATHS[i]}
      name=${p##*/}
      dflag=0; grp=0; num=0; ext=""
      if [ "$dirs_first" == true ] && [ "${E_XTYPE[$p]}" != d ]; then dflag=1; fi
      if [ "$sort_key" == name ]; then
        if [[ $name == ..?* ]]; then grp=2; elif [[ $name == .* ]]; then grp=1; fi
      fi
      case $sort_key in
        size) num=${E_BYTES[$p]:-0} ;;
        time) num=${E_MTIME[$p]:-0} ;;
        type) [[ $name == ?*.* ]] && ext=${name##*.}; ext=${ext,,}; ext=${ext//$'\t'/ } ;;
      esac
      printf '%s\t%s\t%s\t%s\t%s\t%s\0' "$dflag" "$grp" "$num" "$ext" "$i" "$name"
    done | sort "${sort_args[@]}"
  )
  for line in "${order[@]}"; do
    t=${line#*$'\t'}; t=${t#*$'\t'}; t=${t#*$'\t'}; t=${t#*$'\t'}
    p=${ALL_PATHS[${t%%$'\t'*}]}
    parent_of "$p"
    CHILDREN[$REPLY]+="$p$SEP"
  done
}

# ---------------------------------------------------------------------------
# eza look for the default scheme. Colours follow eza's built-in default theme
# (github.com/eza-community/eza, src/theme/default_theme.rs) and honour
# LS_COLORS and EZA_COLORS the same way eza does. EZ maps eza's own colour keys
# (the ones EZA_COLORS uses) to SGR codes.
EZA_MODE=false
declare -A EZ=(
  [di]="1;34" [ex]="1;32" [fi]="" [ln]="36" [or]="31" [pi]="33" [bd]="1;33" [cd]="1;33"
  [so]="1;31" [sp]="33"
  [ur]="1;33" [uw]="1;31" [ux]="1;4;32" [ue]="1;32" [gr]="33" [gw]="31" [gx]="32"
  [tr]="33" [tw]="31" [tx]="32" [su]="35" [sf]="35" [xa]=""
  [nb]="32" [nk]="1;32" [nm]="33" [ng]="31" [nt]="35"
  [ub]="32" [uk]="1;32" [um]="33" [ug]="31" [ut]="35"
  [uu]="1;33" [un]="" [uR]="" [gu]="1;33" [gn]="" [gR]=""
  [ga]="32" [gm]="34" [gd]="31" [gv]="33" [gt]="35" [gi]="2" [gc]="31"
  [xx]="1;90" [da]="34" [hd]="4"
  [im]="35" [vi]="1;35" [mu]="36" [lo]="1;36" [cr]="1;32" [do]="32" [co]="31"
  [tm]="2" [cm]="33" [bu]="1;4;33" [sc]="1;33"
)
declare -A _EZ_NAME _EZ_EXT _EZ_TYPEKEY=(
  [I]=im [V]=vi [M]=mu [L]=lo [C]=cr [D]="do" [Z]=co [T]=tm [O]=cm [B]=bu [S]=sc
)
declare -A EZ_GLOB_EXT EZ_PERM_CACHE EZ_MY_GROUPS
EZ_GLOBS=()            # complex LS_COLORS/EZA_COLORS globs, "pattern<SEP>codes", in order
EZ_FILETYPES=true      # EZA_COLORS=reset:... turns eza's built-in file types off
EZ_ME=""

# File name / extension -> eza file type (generated from eza's src/info/filetype.rs).
ez_load_filetypes() {
  local _k
  for _k in Brewfile bsconfig.json BUILD BUILD.bazel build.gradle build.sbt build.xml Cargo.toml \
    CMakeLists.txt composer.json configure Containerfile Dockerfile Earthfile flake.nix Gemfile \
    GNUmakefile Gruntfile.coffee Gruntfile.js jsconfig.json Justfile justfile Makefile makefile \
    meson.build mix.exs package.json Pipfile PKGBUILD Podfile pom.xml Procfile pyproject.toml \
    Rakefile RoboFile.php SConstruct tsconfig.json Vagrantfile webpack.config.cjs webpack.config.js \
    WORKSPACE; do _EZ_NAME[$_k]=B; done
  for _k in id_dsa id_ecdsa id_ecdsa_sk id_ed25519 id_ed25519_sk id_rsa; do _EZ_NAME[$_k]=C; done
  _EZ_EXT[ninja]=B
  for _k in arw avif bmp cbr cbz cr2 dvi eps fodg gif heic heif ico j2c j2k jfi jfif jif jp2 jpe jpeg jpf \
    jpg jpx jxl kra krz nef odg orf pbm pgm png pnm ppm ps psd pxm raw qoi svg tif tiff webp xcf xpm; do _EZ_EXT[$_k]=I; done
  for _k in avi flv h264 heics m2ts m2v m4v mkv mov mp4 mpeg mpg ogm ogv video vob webm wmv; do _EZ_EXT[$_k]=V; done
  for _k in aac m4a mka mp2 mp3 ogg opus wma; do _EZ_EXT[$_k]=M; done
  for _k in aif aifc aiff alac ape flac pcm wav wv; do _EZ_EXT[$_k]=L; done
  for _k in age asc cer crt csr gpg kbx md5 p12 pem pfx pgp pub sha1 sha224 sha256 sha384 sha512 sig \
    signature; do _EZ_EXT[$_k]=C; done
  for _k in djvu doc docx eml fodp fods fodt fotd gdoc key keynote numbers odp ods odt pages pdf ppt pptx \
    rtf xls xlsm xlsx; do _EZ_EXT[$_k]=D; done
  for _k in 7z ar arj br bz bz2 bz3 cpio deb dmg gz iso lz lz4 lzh lzma lzo phar qcow qcow2 rar rpm tar taz \
    tbz tbz2 tc tgz tlz txz tz xz vdi vhd vhdx vmdk z zip zst; do _EZ_EXT[$_k]=Z; done
  for _k in bak bk bkp crdownload download fcbak fcstd1 fdmdownload part swn swo swp tmp; do _EZ_EXT[$_k]=T; done
  for _k in a bundle class cma cmi cmo cmx dll dylib elc elf ko lib o obj pyc pyd pyo so zwc; do _EZ_EXT[$_k]=O; done
  for _k in applescript as asa awk c c++ c++m cabal cc ccm clj cp cpp cppm cr cs css csx cu cxx cxxm cypher \
    d dart di dpr el elm erl ex exs f f90 fcmacro fcscript fnl for fs fsh fsi fsx gd go gradle \
    groovy gvy h h++ hh hpp hc hs htc hxx inc inl ino ipynb ixx java jl js jsx kt kts kusto less lhs \
    lisp ltx lua m malloy matlab ml mli mn nb p pas php pl pm pod pp prql ps1 psd1 psm1 purs py r rb \
    rs rq sass scala scm scad scss sld sql ss swift tcl tex ts v vb vsh zig; do _EZ_EXT[$_k]=S; done
}

# Apply one LS_COLORS / EZA_COLORS string. $2=true for EZA_COLORS (eza-only keys).
ez_apply_colors() {
  local spec=$1 is_eza=$2 pair key val oldifs=$IFS
  local -a pairs
  if [ "$is_eza" == true ] && [[ $spec == reset || $spec == reset:* ]]; then
    EZ_FILETYPES=false
    spec=${spec#reset}; spec=${spec#:}
  fi
  IFS=:; set -f
  # shellcheck disable=SC2206
  pairs=( $spec )
  set +f; IFS=$oldifs
  for pair in "${pairs[@]}"; do
    [[ $pair == *=* ]] || continue
    key=${pair%%=*}; val=${pair#*=}
    [[ $val =~ ^[0-9\;]*$ ]] || continue          # e.g. ln=target: not a colour
    case $key in
      di|ex|fi|pi|so|bd|cd|ln|or) EZ[$key]=$val ;;
      sn) EZ[nb]=$val; EZ[nk]=$val; EZ[nm]=$val; EZ[ng]=$val; EZ[nt]=$val ;;
      sb) EZ[ub]=$val; EZ[uk]=$val; EZ[um]=$val; EZ[ug]=$val; EZ[ut]=$val ;;
      *)
        if [[ $key == \*.* && ${key:2} != *[\*\?\[]* ]]; then
          EZ_GLOB_EXT[${key:2}]=$val
        elif [[ $key == *[\*\?\[]* ]]; then
          EZ_GLOBS+=("$key$SEP$val")
        elif [ "$is_eza" == true ] && [ -n "${EZ[$key]+x}" ]; then
          EZ[$key]=$val
        fi ;;
    esac
  done
}

ez_init() {
  local g
  EZA_MODE=true
  ez_load_filetypes
  # Timestamps: 256-colour blue #75 (#5fafff), the date blue eza shows. Sent even when terminfo
  # claims fewer colours (eza does the same); only the Linux text console gets plain bright blue.
  if [ "${TERM:-}" == linux ]; then EZ[da]="94"; else EZ[da]="38;5;75"; fi
  [ -n "${LS_COLORS:-}" ] && ez_apply_colors "$LS_COLORS" false
  [ -n "${EZA_COLORS:-${EXA_COLORS:-}}" ] && ez_apply_colors "${EZA_COLORS:-$EXA_COLORS}" true
  EZ_ME=$(id -un 2>/dev/null)
  for g in $(id -Gn 2>/dev/null); do EZ_MY_GROUPS[$g]=1; done
  # Column headers are underlined, like eza's --header.
  ez_sgr hd
  COLOR_PERMISSIONS=$REPLY; COLOR_OWNER_GROUP=$REPLY; COLOR_SIZE=$REPLY
  COLOR_MODIFIED=$REPLY; COLOR_DIRECTORY=$REPLY; COLOR_RESET=$'\e[0m'
}

# $1 = colour key -> REPLY = start sequence ("" when the style is empty).
ez_sgr() {
  if [ -n "${EZ[$1]}" ]; then REPLY=$'\e['"${EZ[$1]}m"; else REPLY=""; fi
}

# Paint $2 with the style of key $1 -> REPLY.
ez_paint() {
  if [ -n "${EZ[$1]}" ]; then REPLY=$'\e['"${EZ[$1]}m$2"$'\e[0m'; else REPLY=$2; fi
}

# Colour a permission string per character, as eza does. $1 = perms, $2 = find type.
# shellcheck disable=SC2209  # bare style keys like cd/tr/ex are strings
ez_perms() {
  local perms=$1 t=$2 cache_key="$1|$2" out="" i c key reg=false
  if [ -n "${EZ_PERM_CACHE[$cache_key]+x}" ]; then REPLY=${EZ_PERM_CACHE[$cache_key]}; return; fi
  [ "$t" == f ] && reg=true
  for (( i = 0; i < ${#perms}; i++ )); do
    c=${perms:i:1}; key=""
    case $i in
      0) case $t in d) key=di ;; l) key=ln ;; p) key=pi ;; s) key=so ;; b) key=bd ;; c) key=cd ;; f) key="fi" ;; *) key=sp ;; esac ;;
      1) [ "$c" == r ] && key=ur ;;
      2) [ "$c" == w ] && key=uw ;;
      3) case $c in x) if $reg; then key=ux; else key=ue; fi ;; s) if $reg; then key=su; else key=sf; fi ;; S) key=sf ;; esac ;;
      4) [ "$c" == r ] && key=gr ;;
      5) [ "$c" == w ] && key=gw ;;
      6) case $c in x) key=gx ;; s|S) key=sf ;; esac ;;
      7) [ "$c" == r ] && key=tr ;;
      8) [ "$c" == w ] && key=tw ;;
      9) case $c in x) key=tx ;; t|T) key=sf ;; esac ;;
      *) key=xa ;;
    esac
    if [ "$c" == - ] && (( i > 0 && i < 10 )); then key=xx; fi
    if [ -n "$key" ]; then ez_paint "$key" "$c"; out+=$REPLY; else out+=$c; fi
  done
  EZ_PERM_CACHE[$cache_key]=$out
  REPLY=$out
}

# Size text (du -h style) coloured by magnitude: number and unit parts.
# shellcheck disable=SC2209  # bare style keys like cd/tr/ex are strings
ez_size() {
  local s=$1 num unit nk uk
  num=${s%[KMGTPE]}; unit=${s#"$num"}
  case $unit in
    '') nk=nb; uk=ub ;; K) nk=nk; uk=uk ;; M) nk=nm; uk=um ;; G) nk=ng; uk=ug ;; *) nk=nt; uk=ut ;;
  esac
  ez_paint "$nk" "$num"; local a=$REPLY
  if [ -n "$unit" ]; then ez_paint "$uk" "$unit"; REPLY=$a$REPLY; else REPLY=$a; fi
}

# eza's file-name style -> REPLY (style key or raw codes after "="). $1 = path, $2 = name.
# shellcheck disable=SC2209  # bare style keys like cd/tr/ex are strings
ez_name_key() {
  local p=$1 name=$2 ext="" lower entry i t
  t=${E_TYPE[$p]}
  case $t in
    d) REPLY=di; return ;;
    f) if [[ ${E_MODE[$p]:3:1} == [xs] ]]; then REPLY=ex; return; fi ;;
    l) if [[ ${E_XTYPE[$p]} == [NL] ]]; then REPLY=or; else REPLY=ln; fi; return ;;
    p) REPLY=pi; return ;;
    s) REPLY=so; return ;;
    b) REPLY=bd; return ;;
    c) REPLY=cd; return ;;
    *) REPLY=sp; return ;;
  esac
  # Regular file: LS_COLORS/EZA_COLORS globs first (later entries win), then eza's file types.
  for (( i = ${#EZ_GLOBS[@]} - 1; i >= 0; i-- )); do
    entry=${EZ_GLOBS[i]}
    # shellcheck disable=SC2053  # the pattern is meant to glob
    if [[ $name == ${entry%%"$SEP"*} ]]; then REPLY="=${entry#*"$SEP"}"; return; fi
  done
  [[ $name == *.* ]] && ext=${name##*.}
  if [ -n "$ext" ] && [ -n "${EZ_GLOB_EXT[$ext]+x}" ]; then REPLY="=${EZ_GLOB_EXT[$ext]}"; return; fi
  if [ "$EZ_FILETYPES" == true ]; then
    lower=${name,,}
    if [[ $lower == readme* ]]; then REPLY=bu; return; fi
    if [ -n "${_EZ_NAME[$name]+x}" ]; then REPLY=${_EZ_TYPEKEY[${_EZ_NAME[$name]}]}; return; fi
    if [ -n "$ext" ] && [ -n "${_EZ_EXT[${ext,,}]+x}" ]; then REPLY=${_EZ_TYPEKEY[${_EZ_EXT[${ext,,}]}]}; return; fi
    if [[ $name == *~ || ( $name == \#* && $name == *\# ) ]]; then REPLY=tm; return; fi
  fi
  REPLY="fi"
}

ez_name() {
  ez_name_key "$1" "$2"
  if [[ $REPLY == =* ]]; then
    local codes=${REPLY#=}
    if [ -n "$codes" ]; then REPLY=$'\e['"${codes}m$2"$'\e[0m'; else REPLY=$2; fi
  else
    ez_paint "$REPLY" "$2"
  fi
}

ez_git() {
  local code=$1 out="" c key i
  if [ "$code" == '*' ]; then ez_paint gm '*'; REPLY="$REPLY "; return; fi
  for (( i = 0; i < 2; i++ )); do
    c=${code:i:1}
    case $c in
      A|'?') key=ga ;; M) key=gm ;; D) key=gd ;; R|C) key=gv ;; T) key=gt ;; U) key=gc ;; '!') key=gi ;; *) key="" ;;
    esac
    if [ -n "$key" ]; then ez_paint "$key" "$c"; out+=$REPLY; else out+=${c:- }; fi
  done
  REPLY=$out
}

ez_owner() {
  local u=$1 g=$2 uk gk
  if [ "$u" == "$EZ_ME" ]; then uk=uu; elif [ "$u" == root ]; then uk=uR; else uk=un; fi
  if [ -n "${EZ_MY_GROUPS[$g]+x}" ]; then gk=gu; elif [ "$g" == root ]; then gk=gR; else gk=gn; fi
  ez_paint "$uk" "$u"; local a=$REPLY
  ez_paint "$gk" "$g"
  REPLY="$a::$REPLY"
}
# ---------------------------------------------------------------------------

# Print one entry (terminal line or CSV row). $1 = path, $2 = parent ("" for root), $3 = tree prefix.
print_entry() {
  local p=$1 parent=$2 prefix=$3
  local bytes=${E_BYTES[$p]:-0} pct=100 pb size_color=$COLOR_SIZE hs bar="" k code acl="" name perms
  perms=${E_PERMS[$p]:-${E_MODE[$p]}}
  if [ "$p" == / ]; then name=/; else name=${p##*/}; fi
  human_size "$bytes"; hs=$REPLY

  if [ "$heatmap" == true ] && [ -n "$parent" ]; then
    pb=${E_BYTES[$parent]:-0}
    if (( pb > 0 )); then pct=$(( bytes * 100 / pb )); else pct=0; fi
    (( pct > 100 )) && pct=100
  fi
  if [ "$heatmap" == true ]; then
    if (( pct >= 50 )); then size_color=$C_HEAT_HIGH
    elif (( pct >= 25 )); then size_color=$C_HEAT_MID
    elif (( pct >= 10 )); then size_color=$C_HEAT_LOW
    fi
  fi
  if [ "$GIT_ENABLED" == true ]; then git_code_for "$p"; code=$REPLY; fi
  if [ "$show_acl" == true ] && [[ $perms == *+ ]]; then
    acl=$(getfacl -p -- "$p" 2>/dev/null | tail -n +2)
  fi

  if [ "$export_csv" == true ]; then
    local row=""
    [ "$show_permissions" == true ] && row+="$perms,"
    [ "$show_usergroup" == true ] && row+="${E_USER[$p]}::${E_GROUP[$p]},"
    row+="$hs,"
    [ "$heatmap" == true ] && row+="$pct,"
    [ "$show_datetime" == true ] && row+="${E_DATE[$p]},"
    [ "$GIT_ENABLED" == true ] && row+="$code,"
    if [ "$show_acl" == true ]; then csv_quote "$(printf '%s' "$acl" | tr '\n' ' ')"; row+="$REPLY,"; fi
    csv_quote "$name"; row+="$REPLY"
    printf '%s\n' "$row" >> "$csv_file"
    return
  fi

  if [ "$EZA_MODE" == true ]; then
    print_entry_eza
    return
  fi

  local out=$prefix
  [ "$show_permissions" == true ] && out+="${COLOR_PERMISSIONS}${perms}${COLOR_RESET} "
  [ "$show_usergroup" == true ] && out+="${COLOR_OWNER_GROUP}${E_USER[$p]}::${E_GROUP[$p]}${COLOR_RESET} "
  out+="${size_color}${hs}${COLOR_RESET} "
  if [ "$heatmap" == true ]; then
    local filled=$(( (pct + 5) / 10 ))
    for (( k = 0; k < 10; k++ )); do if (( k < filled )); then bar+="█"; else bar+="░"; fi; done
    printf -v bar '%3d%% %s' "$pct" "$bar"
    out+="${size_color}${bar}${COLOR_RESET} "
  fi
  [ "$show_datetime" == true ] && out+="${COLOR_MODIFIED}${E_DATE[$p]}${COLOR_RESET} "
  if [ "$GIT_ENABLED" == true ]; then
    case $code in
      '')   out+="   " ;;
      '*')  out+="${C_GIT_DIRTY}* ${COLOR_RESET} " ;;
      '??') out+="${C_GIT_NEW}??${COLOR_RESET} " ;;
      *)    out+="${C_GIT_STAGED}${code:0:1}${COLOR_RESET}${C_GIT_CHANGED}${code:1:1}${COLOR_RESET} " ;;
    esac
  fi
  if [ "${E_XTYPE[$p]}" == d ]; then
    out+="${COLOR_DIRECTORY}${name}${COLOR_RESET}"
  else
    out+="${COLOR_FILE}${name}${COLOR_RESET}"
  fi
  printf '%s\n' "$out"
  [ -n "$acl" ] && printf '%s\n' "${COLOR_OWNER_GROUP}${acl}${COLOR_RESET}"
}

# Terminal line in the eza look (uses print_entry's locals via dynamic scope).
print_entry_eza() {
  local out=""
  if [ -n "$prefix" ]; then ez_paint xx "$prefix"; out=$REPLY; fi
  if [ "$show_permissions" == true ]; then ez_perms "$perms" "${E_TYPE[$p]}"; out+="$REPLY "; fi
  if [ "$show_usergroup" == true ]; then ez_owner "${E_USER[$p]}" "${E_GROUP[$p]}"; out+="$REPLY "; fi
  if [ "$heatmap" == true ] && [ "$size_color" != "$COLOR_SIZE" ]; then
    out+="${size_color}${hs}${COLOR_RESET} "
  else
    ez_size "$hs"; out+="$REPLY "
  fi
  if [ "$heatmap" == true ]; then
    local filled=$(( (pct + 5) / 10 ))
    for (( k = 0; k < 10; k++ )); do if (( k < filled )); then bar+="█"; else bar+="░"; fi; done
    printf -v bar '%3d%% %s' "$pct" "$bar"
    out+="${size_color}${bar}${COLOR_RESET} "
  fi
  if [ "$show_datetime" == true ]; then ez_paint da "${E_DATE[$p]}"; out+="$REPLY "; fi
  if [ "$GIT_ENABLED" == true ]; then
    if [ -z "$code" ]; then out+="   "; else ez_git "$code"; out+="$REPLY "; fi
  fi
  ez_name "$p" "$name"; out+=$REPLY
  printf '%s\n' "$out"
  [ -n "$acl" ] && printf '%s\n' "$acl"
}

print_tree() {
  local dir=$1 prefix=$2 oldifs=$IFS i n kid connector
  local -a kids
  IFS=$SEP; set -f
  # shellcheck disable=SC2206  # intentional split on SEP with globbing off
  kids=( ${CHILDREN[$dir]-} )
  set +f; IFS=$oldifs
  n=${#kids[@]}
  for (( i = 0; i < n; i++ )); do
    kid=${kids[i]}
    connector="├── "
    (( i == n - 1 )) && connector="└── "
    if [ "${E_XTYPE[$kid]}" == d ]; then (( COUNT_DIRS++ )); else (( COUNT_FILES++ )); fi
    print_entry "$kid" "$dir" "${prefix}${connector}"
    if [ -n "${CHILDREN[$kid]-}" ]; then
      if (( i == n - 1 )); then print_tree "$kid" "${prefix}    "; else print_tree "$kid" "${prefix}│   "; fi
    fi
  done
}

# Function to display usage
show_usage() {
  echo "Usage: $0 [options] /path/to/directory"
  printf "  -%s\t\t%s\n" "$FLAG_INCLUDE_FILES" "Include files"
  printf "  -%s max_depth\t%s\n" "$FLAG_MAX_DEPTH" "Set maximum depth for directory traversal (default 3)"
  printf "  -%s\t\t%s\n" "$FLAG_SHOW_PERMISSIONS" "Show permissions"
  printf "  -%s\t\t%s\n" "$FLAG_SHOW_DATETIME" "Show modification date/time"
  printf "  -%s\t\t%s\n" "$FLAG_SHOW_USERGROUP" "Show owner and group"
  printf "  -%s\t\t%s\n" "$FLAG_INCLUDE_HIDDEN" "Include hidden files and directories"
  printf "  -%s csv_file\t%s\n" "$FLAG_EXPORT_CSV" "Export output to a CSV file"
  printf "  -%s scheme\t%s\n" "$FLAG_COLOR_SCHEME" "Select color scheme (default, alternative, christmas, halloween, ghost)"
  printf "  -%s\t\t%s\n" "$FLAG_RANDOM_THEME" "Randomly select a color scheme"
  printf "  -%s\t\t%s\n" "$FLAG_SHOW_ACL" "Show ACL information"
  printf "  -%s key\t%s\n" "$FLAG_SORT" "Sort by: name (default), size, time, type, none"
  printf "  -%s\t\t%s\n" "$FLAG_REVERSE" "Reverse the sort order"
  printf "  -%s\t\t%s\n" "$FLAG_DIRS_FIRST" "List directories before files"
  printf "  -%s\t\t%s\n" "$FLAG_HEATMAP" "Size heat map: colour sizes and show % of parent with a bar"
  printf "  -%s\t\t%s\n" "$FLAG_GIT" "Show git status (inside a git repository)"
  printf "  --color=WHEN\t%s\n" "Colours: auto (default, off when piped), always, never"
  exit 1
}

# Long options are handled before getopts.
color_mode=auto
args=()
for arg in "$@"; do
  case $arg in
    --color=*|--colour=*) color_mode=${arg#*=} ;;
    --color|--colour)     color_mode=always ;;
    *)                    args+=("$arg") ;;
  esac
done
set -- "${args[@]}"
case $color_mode in
  always|yes|force) _XT_COLOR=1 ;;
  never|no|none)    _XT_COLOR=0 ;;
  auto|tty|if-tty)
    if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != dumb ]; then _XT_COLOR=1; else _XT_COLOR=0; fi ;;
  *) echo "Error: --color must be auto, always or never" >&2; exit 1 ;;
esac

# Check if no arguments were provided
if [ $# -eq 0 ]; then
  show_usage
fi

# Initialize default values
include_files=false
max_depth=3
show_permissions=false
show_datetime=false
show_usergroup=false
include_hidden=false
show_acl=false
export_csv=false
csv_file=""
scheme="default"
sort_key=name
sort_reverse=false
dirs_first=false
heatmap=false
show_git=false

# Parse the flags
while getopts "$FLAG_INCLUDE_FILES$FLAG_MAX_DEPTH:$FLAG_SHOW_PERMISSIONS$FLAG_SHOW_DATETIME$FLAG_SHOW_USERGROUP$FLAG_INCLUDE_HIDDEN$FLAG_EXPORT_CSV:$FLAG_COLOR_SCHEME:$FLAG_RANDOM_THEME$FLAG_SHOW_ACL$FLAG_SORT:$FLAG_REVERSE$FLAG_DIRS_FIRST$FLAG_HEATMAP$FLAG_GIT" opt; do
  case $opt in
    "$FLAG_INCLUDE_FILES")    include_files=true ;;
    "$FLAG_MAX_DEPTH")        max_depth=$OPTARG ;;
    "$FLAG_SHOW_PERMISSIONS") show_permissions=true ;;
    "$FLAG_SHOW_DATETIME")    show_datetime=true ;;
    "$FLAG_SHOW_USERGROUP")   show_usergroup=true ;;
    "$FLAG_INCLUDE_HIDDEN")   include_hidden=true ;;
    "$FLAG_EXPORT_CSV")       export_csv=true; csv_file=$OPTARG ;;
    "$FLAG_COLOR_SCHEME")     scheme=$OPTARG ;;
    "$FLAG_RANDOM_THEME")     scheme=$(select_random_theme) ;;
    "$FLAG_SHOW_ACL")         show_acl=true ;;
    "$FLAG_SORT")             sort_key=$OPTARG ;;
    "$FLAG_REVERSE")          sort_reverse=true ;;
    "$FLAG_DIRS_FIRST")       dirs_first=true ;;
    "$FLAG_HEATMAP")          heatmap=true ;;
    "$FLAG_GIT")              show_git=true ;;
    *)                        show_usage ;;
  esac
done
shift $((OPTIND - 1))

# Check if a directory was provided
if [ -z "$1" ]; then
  show_usage
fi
if [ ! -d "$1" ]; then
  echo "Error: $1 is not a directory" >&2
  exit 1
fi
if ! [[ $max_depth =~ ^[0-9]+$ ]]; then
  echo "Error: -$FLAG_MAX_DEPTH needs a whole number, got '$max_depth'" >&2
  exit 1
fi
case $sort_key in
  name|size|time|type|none) ;;
  *) echo "Error: -$FLAG_SORT must be name, size, time, type or none" >&2; exit 1 ;;
esac

# Strip trailing slashes so paths match what find/du print ("dir/" -> "dir").
root=$1
while [[ $root == */ && $root != / ]]; do root=${root%/}; done

set_color_scheme "$scheme"
[ "$scheme" == default ] && [ "$_XT_COLOR" == 1 ] && ez_init
C_HEAT_HIGH=$(tput bold; tput setaf 1)  # >= 50% of parent
C_HEAT_MID=$(tput setaf 208)            # >= 25% (orange; yellow on 8-colour terminals)
C_HEAT_LOW=$(tput setaf 3)              # >= 10%
C_GIT_STAGED=$(tput setaf 2)
C_GIT_CHANGED=$(tput setaf 1)
C_GIT_NEW=$(tput setaf 1)
C_GIT_DIRTY=$(tput setaf 3)

# Print ASCII art based on the selected color scheme
print_ascii_art "$scheme"

collect_entries "$root"
if [ -z "${E_TYPE[$root]+x}" ]; then
  echo "Error: cannot read $root" >&2
  exit 1
fi
[ "$show_git" == true ] && collect_git "$root"
build_children

# Print the column headers
if [ "$export_csv" == true ]; then
  csv_header=""
  [ "$show_permissions" == true ] && csv_header+="${HEADER_PERMISSIONS},"
  [ "$show_usergroup" == true ] && csv_header+="${HEADER_OWNER_GROUP},"
  csv_header+="${HEADER_SIZE},"
  [ "$heatmap" == true ] && csv_header+="${HEADER_USAGE} %,"
  [ "$show_datetime" == true ] && csv_header+="${HEADER_MODIFIED},"
  [ "$GIT_ENABLED" == true ] && csv_header+="${HEADER_GIT},"
  [ "$show_acl" == true ] && csv_header+="${HEADER_ACL},"
  csv_header+="${HEADER_DIRECTORY}"
  printf '%s\n' "$csv_header" > "$csv_file" || exit 1
else
  header=""
  [ "$show_permissions" == true ] && header+="${COLOR_PERMISSIONS}${HEADER_PERMISSIONS}${COLOR_RESET} "
  [ "$show_usergroup" == true ] && header+="${COLOR_OWNER_GROUP}${HEADER_OWNER_GROUP}${COLOR_RESET} "
  header+="${COLOR_SIZE}${HEADER_SIZE}${COLOR_RESET} "
  [ "$heatmap" == true ] && header+="${COLOR_SIZE}${HEADER_USAGE}${COLOR_RESET} "
  [ "$show_datetime" == true ] && header+="${COLOR_MODIFIED}${HEADER_MODIFIED}${COLOR_RESET} "
  [ "$GIT_ENABLED" == true ] && header+="${COLOR_MODIFIED}${HEADER_GIT}${COLOR_RESET} "
  header+="${COLOR_DIRECTORY}${HEADER_DIRECTORY}${COLOR_RESET}"
  [ "$show_acl" == true ] && header+=" ${COLOR_OWNER_GROUP}${HEADER_ACL}${COLOR_RESET}"
  printf '%s\n' "$header"
fi

print_entry "$root" "" ""
print_tree "$root" ""

# Summary line, like tree's report.
if [ "$export_csv" != true ]; then
  human_size "${E_BYTES[$root]:-0}"
  summary="$COUNT_DIRS director$( (( COUNT_DIRS == 1 )) && echo y || echo ies)"
  if [ "$include_files" == true ]; then
    summary+=", $COUNT_FILES file$( (( COUNT_FILES == 1 )) || echo s)"
  fi
  if [ "$EZA_MODE" == true ]; then ez_size "$REPLY"; else REPLY="${COLOR_SIZE}${REPLY}${COLOR_RESET}"; fi
  printf '\n%s, %s total\n' "$summary" "$REPLY"
fi
