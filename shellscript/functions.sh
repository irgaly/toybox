#!/bin/bash

# stderr へ echoする
stderr(){
  echo -e "$@" 1>&2
}

# 簡単なスタックトレースをstderrへ出力
print_stack_trace(){
  stderr "== stack trace =="
  local frame=1
  while caller "$frame" 1>&2; do
    frame=$((frame+1));
  done
}

# stderr にスタックトレースとエラーメッセージを表示して終了
error(){
  print_stack_trace
  (( 0 < $# )) && stderr "$@"
  exit -1
}

# 同値でなければ終了
# usage: assert_eq 3 $#
#        assert_eq 3 $# "error message"
assert_eq(){
  [[ $# != 2 && $# != 3 ]] && error "usage: assert_eq n1 n2 [message]"
  local msg="assert_eq error: [$1] [$2]"
  [[ -n $3 ]] && msg=$3
  [[ $1 != "$2" ]] && error "$msg"
}

# ファイルが存在しなければ終了
assert_exists(){
  (( $# < 1 )) && error "usage: assert_exists file1 ..."
  while (($#)); do
    [[ ! -e $1 ]] && error "[$1] does not exists."
    shift
  done
}

# MacOS以外の環境で走っていたら終了
assert_mac(){
  in_mac || error "this platform is not Mac OS."
}

# OS X 10.8以降の通知センターを用いて通知する
notify(){
  (( $# < 1 || 2 < $# )) && error "usage: notify message\n      notify title message"
  local NOTIFY=$HOME/bin/terminal-notifier.app/Contents/MacOS/terminal-notifier
  local title=$1
  local message=$2
  [[ -z $message ]] && message=$1; title="notify"
  "$NOTIFY" $RANDOM -title "$title" -message "$message"
}

# notifyを用いて通知センターへメッセージを表示したのちスプリプトを終了する
notify_error(){
  notify "$@"
  error "$@"
}

# symbolicリンク全展開
# たどれるまで辿ったパスを返す
# 循環参照で無限ループ入ります
expand_link(){
  assert_eq $# 1
  local path=$1
  local dir=$(dirname "$1")
  [[ -h $path ]] && path=$(expand_link "$(join_path "$dir" "$(readlink "$path")")")
  echo "$(expand_path "$path")"
}

# パスの結合 (文字ベース)
join_path(){
  assert_eq $# 2 "usage: join_path base_dir target_path"
  base=$1
  path=$2
  if [[ $path =~ ^[^/] ]]; then
    [[ $base =~ ^(.*[^/])/+$ ]] && base=${BASH_REMATCH[1]}
    path="$base/$path"
  fi
  echo "$path"
}

# 文字列操作によるパスの展開
# . と .. の展開のみ行います
expand_path(){
  assert_eq $# 1
  local dir=$(dirname "$1")
  local base=$(basename "$1")

  # 特殊処理
  [[ $1 == /.. || $1 == .. ]] && echo "$1" && return  #パスが不正

  # 一般 (再起の終端)
  [[ $base == / ]] && echo "/" && return
  [[ $dir == /. || $dir == / ]] && echo "/$base" && return
  [[ $dir == . ]] && echo "$base" && return

  # 一般 (再起)
  expanded_dir=$(expand_path "$dir")
  path=$expanded_dir/$base
  [[ $base == . ]] && path=$expanded_dir
  [[ $base == .. &&
    ! $expanded_dir =~ ^(.*/)?\.\.$ ]] && path=$(dirname "$expanded_dir")

  # 先頭の"./"は削除
  [[ $path =~ ^\./(.*)$ ]] && path=${BASH_REMATCH[1]}

  echo "$path"
}

# symbolic link/hard linkを考慮した同一ファイルチェック
same_file(){
  assert_eq $# 2
  [[ $1 -ef $2 ]]
}

# 同一ファイルチェック(symbolic linkは辿らない)
same_inode(){
  assert_eq $# 2
  [[ $(inode "$1") == $(inode "$2") ]]
}

# 定義されているfunctionのリストを返す
list_functions(){
  echo "$(compgen -A function)"
}

# 配列の全要素に対して処理を適用し
# 条件を満すものだけを返す
map(){
  (( $# < 2 )) && error "usage: map '[[ \$item == ex ]]' \"\${array[@]}\""
  exp=$1
  shift
  while (($#)); do
    item=$1
    eval "$exp" && echo "$item"
    shift
  done
}

# stdoutの出力をflush
flush(){
  cat -u /dev/null
}

# inode番号取得
inode(){
  assert_eq $# 1
  assert_mac
  stat -f%i "$1"
}

# 環境がMac OSの時にtrue
in_mac(){
  [[ $(uname) == "Darwin" ]]
}

# 環境がLinuxの時にtrue
in_linux(){
  [[ $(uname) == "Linux" ]]
}

# bashスクリプトのunit testを実行する
unit_test(){
  (( $# < 1 )) && error "usage: unit_test target.sh ..."
  assert_exists "$@"

  while (($#)); do
    (
    . "$1" load_tests
    echo "> $1"
    for target in $(map '[[ $item =~ ^_test_.+$ ]]' $(list_functions)); do
      echo -n "run test [$target]..."; flush
      msg=$(eval "$target" 2>&1)
      if (($?)); then
        echo "FAILED"
        echo "$msg"
        exit -1
      fi
      echo "CLEAR"
    done
    ) || exit $?
    shift
  done
}

[[ $1 == "load_tests" ]] && {
  _test_expand_path(){
    assert_eq "$(expand_path "a/b/c/../d/./")" "a/b/d"
    assert_eq "$(expand_path "a/b/../..")" "."
    assert_eq "$(expand_path "/a/b/../..")" "/"
    assert_eq "$(expand_path "/a./ /\\/b../.c/..d")" "/a./ /\\/b../.c/..d" #パーステスト
    assert_eq "$(expand_path "/./../a/./.././a/..")" "/.."  # 特殊
    assert_eq "$(expand_path "/../b/././../../a")" "/../../a"  # 特殊
    assert_eq "$(expand_path "../b/././../../a")" "../../a"  # 特殊
    return 0
  }

  _test_join_path(){
    assert_eq "$(join_path "a" "b")" "a/b"
    assert_eq "$(join_path "a" "/b")" "/b"
    assert_eq "$(join_path "a/b/" "c")" "a/b/c"
    assert_eq "$(join_path "a/b" "c")" "a/b/c"
    assert_eq "$(join_path "a/b///" "c")" "a/b/c"
    return 0
  }

  _test_expand_link(){
    (cd /tmp
    ln -s _test_file _test_link1
    ln -s _test_link1 _test_link2)
    assert_eq "$(expand_link "/tmp/_test_link2")" "/tmp/_test_file"
    (cd /tmp
    unlink _test_link1
    unlink _test_link2)
    return 0
  }
}

# 正常にsourceできたら$?を0に
$()
