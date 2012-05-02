#!/bin/bash
#
# Serval Project testing framework for Bash shell
# Copyright 2012 Paul Gardner-Stephen
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 
# This file is sourced by all testing scripts.  A typical test script looks
# like this:
#
# #!/bin/bash
# source testframework.sh
# setup() {
#   export BLAH_CONFIG=$TFWTMP/blah.conf
#   echo "username=$LOGNAME" >$BLAH_CONFIG
# }
# teardown() {
#   # $TFWTMP is always removed after every test, so no need to
#   # remove blah.conf ourselves.
# }
# doc_feature1='Feature one works'
# test_feature1() {
#   execute programUnderTest --feature1 arg1 arg2
#   assertExitStatus '==' 0
#   assertRealTime --message='ran in under half a second' '<=' 0.5
#   assertStdoutIs ""
#   assertStderrIs ""
# }
# doc_feature2='Feature two fails with status 1'
# setup_feature2() {
#   # Overrides setup(), so we have to call it ourselves explicitly
#   # here if we still want it.
#   setup
#   echo "option=specialValue" >>$BLAH_CONFIG
# }
# test_feature2() {
#   execute programUnderTest --feature2 arg1 arg2
#   assertExitStatus '==' 1
#   assertStdoutIs -e "Response:\tok\n"
#   assertStderrGrep "^ERROR: missing arg3$"
# }
# runTests "$@"

usage() {
   echo "Usage: ${0##*/} [-t|--trace] [-v|--verbose] [--filter=prefix] [--]"
}

runTests() {
   _tfw_stdout=1
   _tfw_stderr=2
   _tfw_checkBashVersion
   _tfw_trace=false
   _tfw_verbose=false
   _tfw_invoking_script=$(abspath "${BASH_SOURCE[1]}")
   _tfw_suite_name="${_tfw_invoking_script##*/}"
   _tfw_cwd=$(abspath "$PWD")
   _tfw_logfile="$_tfw_cwd/test.$_tfw_suite_name.log"
   local allargs="$*"
   local filter=
   while [ $# -ne 0 ]; do
      case "$1" in
      --help) usage; exit 0;;
      -t|--trace) _tfw_trace=true;;
      -v|--verbose) _tfw_verbose=true;;
      --filter=*) filter="${1#*=}";;
      --) shift; break;;
      --*) _tfw_fatal "unsupported option: $1";;
      *) _tfw_fatal "spurious argument: $1";;
      esac
      shift
   # Kick off the log file.
   done
   {
      date
      echo "$0 $allargs"
   } >$_tfw_logfile
   # Iterate through all test cases.
   local testcount=0
   local passcount=0
   local testName
   for testName in `_tfw_find_tests`
   do
      _tfw_test_name="$testName"
      if [ -z "$filter" -o "${_tfw_test_name#$filter}" != "$_tfw_test_name" ]; then
         let testcount=testcount+1
         (
            local docvar="doc_$_tfw_test_name"
            _tfw_echo -n "$testcount. ${!docvar:-$_tfw_test_name}..."
            trap '_tfw_status=$?; _tfw_teardown; exit $_tfw_status' 0 1 2 15
            _tfw_result=ERROR
            _tfw_setup
            _tfw_result=FAIL
            _tfw_phase=testcase
            echo "# call test_$_tfw_test_name()"
            $_tfw_trace && set -x
            test_$_tfw_test_name
            _tfw_result=PASS
            exit 0
         )
         local stat=$?
         case $stat in
         255) exit 255;; # _tfw_fatal was called
         254) _tfw_echo " ERROR";; # _tfw_failexit was called in setup or teardown or _tfw_error was called anywhere
         0) _tfw_echo " PASS"; let passcount=passcount+1;;
         *) _tfw_echo " FAIL";;
         esac
      fi
   done
   s=$([ $testcount -eq 1 ] || echo s)
   _tfw_echo "$testcount test$s, $passcount passed"
   [ $passcount -eq $testcount ]
}

# The following functions can be overridden by a test script to provide a
# default fixture for all test cases.

setup() {
   :
}

teardown() {
   :
}

# The following functions are provided to facilitate writing test cases and
# fixtures.

# Echo the absolute path (containing symlinks if given) of the given
# file/directory, which does not have to exist or even be accessible.
abspath() {
   _tfw_abspath -L "$1"
}

# Echo the absolute path (resolving all symlinks) of the given file/directory,
# which does not have to exist or even be accessible.
realpath() {
   _tfw_abspath -P "$1"
}

execute() {
   echo "# execute $*"
   _tfw_getopts execute "$@"
   shift $_tfw_getopts_shift
   _tfw_execute "$@"
}

executeOk() {
   echo "# executeOk $*"
   _tfw_getopts executeok "$@"
   _tfw_opt_exit_status=0
   _tfw_dump_on_fail --stderr
   shift $_tfw_getopts_shift
   _tfw_execute "$@"
}

assert() {
   _tfw_getopts assert "$@"
   shift $_tfw_getopts_shift
   _tfw_assert "$@" || _tfw_failexit
   echo "# assert $*"
   return 0
}

assertExpr() {
   _tfw_getopts assertexpr "$@"
   shift $_tfw_getopts_shift
   local awkexpr=$(_tfw_expr_to_awkexpr "$@")
   _tfw_message="${_tfw_message+$_tfw_message }($awkexpr)"
   _tfw_assert _tfw_eval_awkexpr "$awkexpr" || _tfw_failexit
   echo "# assert $awkexpr"
   return 0
}

fail() {
   _tfw_getopts fail "$@"
   shift $_tfw_getopts_shift
   [ $# -ne 0 ] && _tfw_failmsg "$1"
   _tfw_backtrace
   _tfw_failexit
}

error() {
   _tfw_getopts error "$@"
   shift $_tfw_getopts_shift
   [ $# -ne 0 ] && _tfw_errormsg "$1"
   _tfw_backtrace
   _tfw_errorexit
}

fatal() {
   [ $# -eq 0 ] && set -- "no reason given"
   _tfw_fatalmsg "$@"
   _tfw_backtrace
   _tfw_fatalexit
}

tfw_cat() {
   local header=
   local show_nonprinting=
   for file; do
      case $file in
      --stdout) 
         echo "#--- ${header:-stdout of ${_tfw_execute_argv0##*/}} ---"
         cat $show_nonprinting $_tfw_tmp/stdout
         echo "#---"
         header=
         show_nonprinting=
         ;;
      --stderr) 
         echo "#--- ${header:-stderr of ${_tfw_execute_argv0##*/}} ---"
         cat $show_nonprinting $_tfw_tmp/stderr
         echo "#---"
         header=
         show_nonprinting=
         ;;
      --header=*) header="${1#*=}";;
      -v|--show-nonprinting) show_nonprinting=-v;;
      *)
         echo "#--- ${header:-$file} ---"
         cat $show_nonprinting "$file"
         echo "#---"
         header=
         show_nonprinting=
         ;;
      esac
   done
}

assertExitStatus() {
   _tfw_getopts assertexitstatus "$@"
   shift $_tfw_getopts_shift
   [ -z "$_tfw_message" ] && _tfw_message="exit status of ${_tfw_execute_argv0##*/} ($_tfw_exitStatus) $*"
   _tfw_assertExpr "$_tfw_exitStatus" "$@" || _tfw_failexit
   echo "# assert $_tfw_message"
   return 0
}

assertRealTime() {
   _tfw_getopts assertrealtime "$@"
   shift $_tfw_getopts_shift
   [ -z "$_tfw_message" ] && _tfw_message="real execution time of ${_tfw_execute_argv0##*/} ($realtime) $*"
   _tfw_assertExpr "$realtime" "$@" || _tfw_failexit
   echo "# assert $_tfw_message"
   return 0
}

replayStdout() {
   cat $_tfw_tmp/stdout
}

replayStderr() {
   cat $_tfw_tmp/stderr
}

assertStdoutIs() {
   _tfw_assert_stdxxx_is stdout "$@" || _tfw_failexit
}

assertStderrIs() {
   _tfw_assert_stdxxx_is stderr "$@" || _tfw_failexit
}

assertStdoutLineCount() {
   _tfw_assert_stdxxx_linecount stdout "$@" || _tfw_failexit
}

assertStderrLineCount() {
   _tfw_assert_stdxxx_linecount stderr "$@" || _tfw_failexit
}

assertStdoutGrep() {
   _tfw_assert_stdxxx_grep stdout "$@" || _tfw_failexit
}

assertStderrGrep() {
   _tfw_assert_stdxxx_grep stderr "$@" || _tfw_failexit
}

assertGrep() {
   _tfw_getopts assertgrep "$@"
   shift $_tfw_getopts_shift
   if [ $# -ne 2 ]; then
      _tfw_error "incorrect arguments"
      return 254
   fi
   _tfw_assert_grep "$1" "$1" "$2" || _tfw_failexit
}

# Internal (private) functions that are not to be invoked directly from test
# scripts.

# Utility for setting shopt variables and restoring their original value:
#     _tfw_shopt -s extglob -u extdebug
#     ...
#     _tfw_shopt_restore
_tfw_shopt() {
   if [ -n "$_tfw_shopt_orig" ]; then
      _tfw_fatal "unrestored shopt settings: $_tfw_shopt_orig"
   fi
   _tfw_shopt_orig=
   local op=s
   while [ $# -ne 0 ]
   do
      case "$1" in
      -s) op=s;;
      -u) op=u;;
      *)
         local opt="$1"
         _tfw_shopt_orig="${restore:+$restore; }shopt -$(shopt -q $opt && echo s || echo u) $opt"
         shopt -$op $opt
         ;;
      esac
      shift
   done
}
_tfw_shopt_restore() {
   if [ -n "$_tfw_shopt_orig" ]; then
      eval "$_tfw_shopt_orig"
      _tfw_shopt_orig=
   fi
}

# The rest of this file is parsed for extended glob patterns.
_tfw_shopt -s extglob

# Echo the absolute path of the given path, using only Bash builtins.
_tfw_abspath() {
   cdopt=-L
   if [ $# -gt 1 -a "${1:0:1}" = - ]; then
      cdopt="$1"
      shift
   fi
   case "$1" in
   */)
      builtin echo $(_tfw_abspath $cdopt "${1%/}")/
      ;;
   /*/*) 
      if [ -d "$1" ]; then
         (CDPATH= builtin cd $cdopt "$1" && builtin echo "$PWD")
      else
         builtin echo $(_tfw_abspath $cdopt "${1%/*}")/"${1##*/}"
      fi
      ;;
   /*)
      echo "$1"
      ;;
   */*)
      if [ -d "$1" ]; then
         (CDPATH= builtin cd $cdopt "$1" && builtin echo "$PWD")
      else
         builtin echo $(_tfw_abspath $cdopt "${1%/*}")/"${1##*/}"
      fi
      ;;
   . | ..)
      (CDPATH= builtin cd $cdopt "$1" && builtin echo "$PWD")
      ;;
   *)
      (CDPATH= builtin cd $cdopt . && builtin echo "$PWD/$1")
      ;;
   esac
}

_tfw_setup() {
   _tfw_phase=setup
   _tfw_tmp=/tmp/_tfw-$$
   mkdir $_tfw_tmp
   exec <&- 5>&1 5>&2 >$_tfw_tmp/log.stdout 2>$_tfw_tmp/log.stderr 6>$_tfw_tmp/log.xtrace
   BASH_XTRACEFD=6
   _tfw_stdout=5
   _tfw_stderr=5
   if $_tfw_verbose; then
      # These tail processes will die when the test case's subshell exits.
      tail --pid=$$ --follow $_tfw_tmp/log.stdout >&$_tfw_stdout 2>/dev/null &
      tail --pid=$$ --follow $_tfw_tmp/log.stderr >&$_tfw_stderr 2>/dev/null &
   fi
   export TFWTMP=$_tfw_tmp/tmp
   mkdir $TFWTMP
   cd $TFWTMP
   echo '# SETUP'
   case `type -t setup_$_tfw_test_name` in
   function)
      echo "# call setup_$_tfw_test_name()"
      $_tfw_trace && set -x
      setup_$_tfw_test_name $_tfw_test_name
      set +x
      ;;
   *)
      echo "# call setup($_tfw_test_name)"
      $_tfw_trace && set -x
      setup $_tfw_test_name
      set +x
      ;;
   esac
   echo '# END SETUP'
}

_tfw_teardown() {
   _tfw_phase=teardown
   echo '# TEARDOWN'
   case `type -t teardown_$_tfw_test_name` in
   function)
      echo "# call teardown_$_tfw_test_name()"
      $_tfw_trace && set -x
      teardown_$_tfw_test_name
      set +x
      ;;
   *)
      echo "# call teardown($_tfw_test_name)"
      $_tfw_trace && set -x
      teardown $_tfw_test_name
      set +x
      ;;
   esac
   echo '# END TEARDOWN'
   {
      local banner="==================== $_tfw_test_name ===================="
      echo "$banner"
      echo "TEST RESULT: $_tfw_result"
      echo '++++++++++ log.stdout ++++++++++'
      cat $_tfw_tmp/log.stdout
      echo '++++++++++'
      echo '++++++++++ log.stderr ++++++++++'
      cat $_tfw_tmp/log.stderr
      echo '++++++++++'
      if $_tfw_trace; then
         echo '++++++++++ log.xtrace ++++++++++'
         cat $_tfw_tmp/log.xtrace
         echo '++++++++++'
      fi
      echo "${banner//[^=]/=}"
   } >>$_tfw_logfile
   rm -rf $_tfw_tmp
}

_tfw_execute() {
   _tfw_execute_argv0="$1"
   { time -p "$@" >$_tfw_tmp/stdout 2>$_tfw_tmp/stderr ; } 2>$_tfw_tmp/times
   _tfw_exitStatus=$?
   # Deal with exit status.
   if [ -n "$_tfw_opt_exit_status" ]; then
      _tfw_message="exit status of ${_tfw_execute_argv0##*/} ($_tfw_exitStatus) is $_tfw_opt_exit_status"
      _tfw_dump_stderr_on_fail=true
      _tfw_assert [ "$_tfw_exitStatus" -eq "$_tfw_opt_exit_status" ] || _tfw_failexit
      echo "# assert $_tfw_message"
   else
      echo "# exit status of ${_tfw_execute_argv0##*/} = $_tfw_exitStatus"
   fi
   # Parse execution time report.
   if ! _tfw_parse_times_to_milliseconds real realtime_ms ||
      ! _tfw_parse_times_to_milliseconds user usertime_ms ||
      ! _tfw_parse_times_to_milliseconds sys systime_ms
   then
      echo '# malformed output from time:'
      tfw_cat --header=times -v $_tfw_tmp/times
   fi
   return 0
}

_tfw_parse_times_to_milliseconds() {
   local label="$1"
   local var="$2"
   local milliseconds=$(awk '$1 == "'"$label"'" {
         value = $2
         minutes = 0
         if (match(value, "[0-9]+m")) {
            minutes = substr(value, RSTART, RLENGTH - 1)
            value = substr(value, 1, RSTART - 1) substr(value, RSTART + RLENGTH)
         }
         if (substr(value, length(value)) == "s") {
            value = substr(value, 1, length(value) - 1)
         }
         if (match(value, "^[0-9]+(\.[0-9]+)?$")) {
            seconds = value + 0
            print (minutes * 60 + seconds) * 1000
         }
      }' $_tfw_tmp/times)
   [ -z "$milliseconds" ] && return 1
   [ -n "$var" ] && eval $var=$milliseconds
   return 0
}

_tfw_assert() {
   if ! "$@"; then
      _tfw_failmsg "assertion failed: ${_tfw_message:-$*}"
      _tfw_backtrace
      return 1
   fi
   return 0
}

declare -a _tfw_opt_dump_on_fail

_tfw_dump_on_fail() {
   for arg; do
      local _found=false
      local _f
      for _f in "${_tfw_opt_dump_on_fail[@]}"; do
         if [ "$_f" = "$arg" ]; then
            _found=true
            break
         fi
      done
      $_found || _tfw_opt_dump_on_fail+=("$arg")
   done
}

_tfw_getopts() {
   local context="$1"
   shift
   _tfw_message=
   _tfw_opt_dump_on_fail=()
   _tfw_opt_error_on_fail=false
   _tfw_opt_exit_status=
   _tfw_opt_matches=
   _tfw_opt_line=
   _tfw_getopts_shift=0
   while [ $# -ne 0 ]; do
      case "$context:$1" in
      *:--stdout) _tfw_dump_on_fail --stdout;;
      *:--stderr) _tfw_dump_on_fail --stderr;;
      assert*:--dump-on-fail=*) _tfw_dump_on_fail "${1#*=}";;
      execute:--exit-status=*) _tfw_opt_exit_status="${1#*=}";;
      assert*:--error-on-fail) _tfw_opt_error_on_fail=true;;
      assert*:--message=*) _tfw_message="${1#*=}";;
      assertgrep:--matches=*) _tfw_opt_matches="${1#*=}";;
      assertfilecontent:--line=*) _tfw_opt_line="${1#*=}";;
      *:--) let _tfw_getopts_shift=_tfw_getopts_shift+1; shift; break;;
      *:--*) _tfw_error "unsupported option: $1";;
      *) break;;
      esac
      let _tfw_getopts_shift=_tfw_getopts_shift+1
      shift
   done
}

_tfw_expr_to_awkexpr() {
   local awkexpr=
   for arg; do
      if [ -z "${arg//[0-9]}" ]; then
         awkexpr="${awkexpr:+$awkexpr }$arg"
      else
         case $arg in
         '==' | '!=' | '<' | '<=' | '>' | '>=' | \
         '~' | '!~' | '&&' | '||' | '!' )
            awkexpr="${awkexpr:+$awkexpr }$arg"
            ;;
         *)
            arg=${arg//\\/\\\\} #} restore Vim syntax highlighting
            arg=${arg//"/\\"}
            awkexpr="${awkexpr:+$awkexpr }\"$arg\""
            ;;
         esac
      fi
   done
   echo $awkexpr
}

_tfw_eval_awkexpr() {
   local awkerrs # on separate line so we don't lose exit status
   awkerrs=$(awk "BEGIN { exit(($*) ? 0 : 1) }" </dev/null 2>&1)
   local stat=$?
   if [ -n "$awkerrs" ]; then
      _tfw_error "invalid expression: $*"
      stat=254
   fi
   return $stat
}

_tfw_assertExpr() {
   local awkexpr=$(_tfw_expr_to_awkexpr "$@")
   _tfw_assert _tfw_eval_awkexpr "$awkexpr" || _tfw_failexit
}

_tfw_assert_stdxxx_is() {
   local qual="$1"
   shift
   _tfw_getopts assertfilecontent --$qual "$@"
   shift $((_tfw_getopts_shift - 1))
   if [ $# -lt 1 ]; then
      _tfw_error "incorrect arguments"
      return 254
   fi
   _tfw_shopt -s extglob
   case "$_tfw_opt_line" in
   +([0-9]))
      sed -n -e "${_tfw_opt_line}p" "$_tfw_tmp/$qual" >"$_tfw_tmp/content"
      ;;
   '')
      ln -f "$_tfw_tmp/$qual" "$_tfw_tmp/content"
      ;;
   *)
      _tfw_error "unsupported value for --line=$_tfw_opt_line"
      _tfw_backtrace
      _tfw_shopt_restore
      return 254
      ;;
   esac
   _tfw_shopt_restore
   local message="${_tfw_message:-${_tfw_opt_line:+line $_tfw_opt_line of }$qual of ${_tfw_execute_argv0##*/} is $*}"
   echo -n "$@" >$_tfw_tmp/stdxxx_is.tmp
   if ! cmp --quiet $_tfw_tmp/stdxxx_is.tmp "$_tfw_tmp/content"; then
      _tfw_failmsg "assertion failed: $message"
      _tfw_backtrace
      return 1
   fi
   echo "# assert $message"
   return 0
}

_tfw_assert_stdxxx_linecount() {
   local qual="$1"
   shift
   _tfw_getopts assertfilecontent --$qual "$@"
   shift $((_tfw_getopts_shift - 1))
   if [ $# -lt 1 ]; then
      _tfw_error "incorrect arguments"
      return 254
   fi
   local lineCount=$(( $(cat $_tfw_tmp/$qual | wc -l) + 0 ))
   [ -z "$_tfw_message" ] && _tfw_message="$qual line count ($lineCount) $*"
   _tfw_assertExpr "$lineCount" "$@" || _tfw_failexit
   echo "# assert $_tfw_message"
   return 0
}

_tfw_assert_stdxxx_grep() {
   local qual="$1"
   shift
   _tfw_getopts assertgrep --$qual "$@"
   shift $((_tfw_getopts_shift - 1))
   if [ $# -ne 1 ]; then
      _tfw_error "incorrect arguments"
      return 254
   fi
   _tfw_assert_grep "$qual of ${_tfw_execute_argv0##*/}" $_tfw_tmp/$qual "$@"
}

_tfw_assert_grep() {
   local label="$1"
   local file="$2"
   local pattern="$3"
   local message=
   local matches=$(( $(grep --regexp="$pattern" "$file" | wc -l) + 0 ))
   local done=false
   local ret=0
   _tfw_shopt -s extglob
   case "$_tfw_opt_matches" in
   '')
      done=true
      message="${_tfw_message:-$label contains a line matching \"$pattern\"}"
      if [ $matches -ne 0 ]; then
         echo "# assert $message"
      else
         _tfw_failmsg "assertion failed: $message"
         ret=1
      fi
      ;;
   esac
   case "$_tfw_opt_matches" in
   +([0-9]))
      done=true
      local s=$([ $_tfw_opt_matches -ne 1 ] && echo s)
      message="${_tfw_message:-$label contains exactly $_tfw_opt_matches line$s matching \"$pattern\"}"
      if [ $matches -eq $_tfw_opt_matches ]; then
         echo "# assert $message"
      else
         _tfw_failmsg "assertion failed: $message"
         ret=1
      fi
      ;;
   esac
   case "$_tfw_opt_matches" in
   +([0-9])-*([0-9]))
      done=true
      local bound=${_tfw_opt_matches%-*}
      local s=$([ $bound -ne 1 ] && echo s)
      message="${_tfw_message:-$label contains at least $bound line$s matching \"$pattern\"}"
      if [ $matches -ge $bound ]; then
         echo "# assert $message"
      else
         _tfw_failmsg "assertion failed: $message"
         ret=1
      fi
      ;;
   esac
   case "$_tfw_opt_matches" in
   *([0-9])-+([0-9]))
      done=true
      local bound=${_tfw_opt_matches#*-}
      local s=$([ $bound -ne 1 ] && echo s)
      message="${_tfw_message:-$label contains at most $bound line$s matching \"$pattern\"}"
      if [ $matches -le $bound ]; then
         echo "# assert $message"
      else
         _tfw_failmsg "assertion failed: $message"
         ret=1
      fi
      ;;
   esac
   if ! $done; then
      _tfw_error "unsupported value for --matches=$_tfw_opt_matches"
      ret=254
   fi
   _tfw_shopt_restore
   if [ $ret -ne 0 ]; then
      _tfw_backtrace
   fi
   return $ret
}

# Write to the real stdout of the test script.
_tfw_echo() {
   echo "$@" >&$_tfw_stdout
}

# Write a message to the real stderr of the test script, so the user sees it
# immediately.  Also write the message to the test log, so it can be recovered
# later.
_tfw_echoerr() {
   echo "$@" >&$_tfw_stderr
   if [ $_tfw_stderr -ne 2 ]; then
      echo "$@" >&2
   fi
}

_tfw_checkBashVersion() {
   [ -z "$BASH_VERSION" ] && _tfw_fatal "not running in Bash (/bin/bash) shell"
   if [ -n "${BASH_VERSINFO[*]}" ]; then
      [ ${BASH_VERSINFO[0]} -gt 3 ] && return 0
      if [ ${BASH_VERSINFO[0]} -eq 3 ]; then
         [ ${BASH_VERSINFO[1]} -gt 2 ] && return 0
         if [ ${BASH_VERSINFO[1]} -eq 2 ]; then
            [ ${BASH_VERSINFO[2]} -ge 48 ] && return 0
         fi
      fi
   fi
   _tfw_fatal "unsupported Bash version: $BASH_VERSION"
}

# Return a list of test names in the order that the test_TestName functions were
# defined.
_tfw_find_tests() {
   _tfw_shopt -s extdebug
   builtin declare -F |
      sed -n -e '/^declare -f test_./s/^declare -f test_//p' |
      while read name; do builtin declare -F "test_$name"; done |
      sort --key 2,2n --key 3,3 |
      sed -e 's/^test_//' -e 's/[    ].*//'
   _tfw_shopt_restore
}

# A "fail" event occurs when any assertion fails, and indicates that the test
# has not passed.  Other tests may still proceed.  A "fail" event during setup
# or teardown is treated as an error, not a failure.

_tfw_failmsg() {
   # A failure during setup or teardown is treated as an error.
   case $_tfw_phase in
   testcase)
      if ! $_tfw_opt_error_on_fail; then
         echo "FAIL: $*"
         return 0;
      fi
      ;;
   esac
   echo "ERROR: $*"
}

_tfw_backtrace() {
   echo '#--- backtrace ---'
   local -i up=1
   while [ "${BASH_SOURCE[$up]}" == "${BASH_SOURCE[0]}" ]; do
      let up=up+1
   done
   local -i i=0
   while [ $up -lt ${#FUNCNAME[*]} -a "${BASH_SOURCE[$up]}" != "${BASH_SOURCE[0]}" ]; do
      echo "[$i] ${FUNCNAME[$(($up-1))]}() called from ${FUNCNAME[$up]}() at line ${BASH_LINENO[$(($up-1))]} of ${BASH_SOURCE[$up]}"
      let up=up+1
      let i=i+1
   done
   echo '#---'
}

_tfw_failexit() {
   # When exiting a test case due to a failure, log any diagnostic output that
   # has been requested.
   tfw_cat "${_tfw_opt_dump_on_fail[@]}"
   # A failure during setup or teardown is treated as an error.
   case $_tfw_phase in
   testcase)
      if ! $_tfw_opt_error_on_fail; then
         exit 1
      fi
      ;;
   esac
   _tfw_errorexit
}

# An "error" event prevents a test from running, so it neither passes nor fails.
# Other tests may still proceed.

_tfw_errormsg() {
   [ $# -eq 0 ] && set -- "(no message)"
   local -i up=1
   while true; do
      case ${FUNCNAME[$up]} in
      _tfw_*) let up=up+1;;
      *) break;;
      esac
   done
   echo "ERROR in ${FUNCNAME[$up]}: $*"
}

_tfw_error() {
   _tfw_errormsg "ERROR: $*"
   _tfw_backtrace
   _tfw_errorexit
}

_tfw_errorexit() {
   # Do not exit process during teardown
   _tfw_result=ERROR
   case $_tfw_phase in
   teardown) [ $_tfw_status -lt 254 ] && _tfw_status=254;;
   *) exit 254;;
   esac
}

# A "fatal" event stops the entire test run, and generally indicates an
# insurmountable problem in the test script or in the test framework itself.

_tfw_fatalmsg() {
   _tfw_echoerr "${BASH_SOURCE[1]}: FATAL: $*"
}

_tfw_fatal() {
   [ $# -eq 0 ] && set -- exiting
   _tfw_echoerr "${BASH_SOURCE[1]}: FATAL: $*"
   _tfw_fatalexit
}

_tfw_fatalexit() {
   exit 255
}

# Restore the caller's shopt preferences before returning.
_tfw_shopt_restore
