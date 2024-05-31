include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


macro(C_supports_sanitizers)
  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND NOT WIN32)
    set(SUPPORTS_UBSAN ON)
  else()
    set(SUPPORTS_UBSAN OFF)
  endif()

  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND WIN32)
    set(SUPPORTS_ASAN OFF)
  else()
    set(SUPPORTS_ASAN ON)
  endif()
endmacro()

macro(C_setup_options)
  option(C_ENABLE_HARDENING "Enable hardening" ON)
  option(C_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    C_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    C_ENABLE_HARDENING
    OFF)

  C_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR C_PACKAGING_MAINTAINER_MODE)
    option(C_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(C_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(C_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(C_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(C_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(C_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(C_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(C_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(C_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(C_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(C_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(C_ENABLE_PCH "Enable precompiled headers" OFF)
    option(C_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(C_ENABLE_IPO "Enable IPO/LTO" ON)
    option(C_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(C_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(C_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(C_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(C_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(C_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(C_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(C_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(C_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(C_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(C_ENABLE_PCH "Enable precompiled headers" OFF)
    option(C_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      C_ENABLE_IPO
      C_WARNINGS_AS_ERRORS
      C_ENABLE_USER_LINKER
      C_ENABLE_SANITIZER_ADDRESS
      C_ENABLE_SANITIZER_LEAK
      C_ENABLE_SANITIZER_UNDEFINED
      C_ENABLE_SANITIZER_THREAD
      C_ENABLE_SANITIZER_MEMORY
      C_ENABLE_UNITY_BUILD
      C_ENABLE_CLANG_TIDY
      C_ENABLE_CPPCHECK
      C_ENABLE_COVERAGE
      C_ENABLE_PCH
      C_ENABLE_CACHE)
  endif()

  C_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (C_ENABLE_SANITIZER_ADDRESS OR C_ENABLE_SANITIZER_THREAD OR C_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(C_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(C_global_options)
  if(C_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    C_enable_ipo()
  endif()

  C_supports_sanitizers()

  if(C_ENABLE_HARDENING AND C_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR C_ENABLE_SANITIZER_UNDEFINED
       OR C_ENABLE_SANITIZER_ADDRESS
       OR C_ENABLE_SANITIZER_THREAD
       OR C_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${C_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${C_ENABLE_SANITIZER_UNDEFINED}")
    C_enable_hardening(C_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(C_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(C_warnings INTERFACE)
  add_library(C_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  C_set_project_warnings(
    C_warnings
    ${C_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  if(C_ENABLE_USER_LINKER)
    include(cmake/Linker.cmake)
    C_configure_linker(C_options)
  endif()

  include(cmake/Sanitizers.cmake)
  C_enable_sanitizers(
    C_options
    ${C_ENABLE_SANITIZER_ADDRESS}
    ${C_ENABLE_SANITIZER_LEAK}
    ${C_ENABLE_SANITIZER_UNDEFINED}
    ${C_ENABLE_SANITIZER_THREAD}
    ${C_ENABLE_SANITIZER_MEMORY})

  set_target_properties(C_options PROPERTIES UNITY_BUILD ${C_ENABLE_UNITY_BUILD})

  if(C_ENABLE_PCH)
    target_precompile_headers(
      C_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(C_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    C_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(C_ENABLE_CLANG_TIDY)
    C_enable_clang_tidy(C_options ${C_WARNINGS_AS_ERRORS})
  endif()

  if(C_ENABLE_CPPCHECK)
    C_enable_cppcheck(${C_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(C_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    C_enable_coverage(C_options)
  endif()

  if(C_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(C_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(C_ENABLE_HARDENING AND NOT C_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR C_ENABLE_SANITIZER_UNDEFINED
       OR C_ENABLE_SANITIZER_ADDRESS
       OR C_ENABLE_SANITIZER_THREAD
       OR C_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    C_enable_hardening(C_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()
