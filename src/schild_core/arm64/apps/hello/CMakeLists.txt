cmake_minimum_required(VERSION 3.16.0)
project(hello C)

find_package(musllibc REQUIRED)
find_package(util_libs REQUIRED)
find_package(seL4_libs REQUIRED)

musllibc_setup_build_environment_with_sel4runtime()
sel4_import_libsel4()
util_libs_import_libraries()
seL4_libs_import_libraries()

add_executable(hello src/main.c)
target_link_libraries(hello PRIVATE sel4_autoconf muslc sel4 sel4runtime)
target_compile_options(hello PRIVATE -g)

include(rootserver)
DeclareRootserver(hello)
