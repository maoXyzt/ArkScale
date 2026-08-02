cmake_minimum_required(VERSION 3.5.0)
project(arkscale_bridge)

add_library(arkscale_bridge SHARED napi_init.cpp)
set_target_properties(arkscale_bridge PROPERTIES SKIP_BUILD_RPATH TRUE)
add_library(arkscale_smoke SHARED IMPORTED)
set_target_properties(arkscale_smoke PROPERTIES
    IMPORTED_LOCATION "${CMAKE_CURRENT_SOURCE_DIR}/../../../libs/arm64-v8a/libarkscale_smoke.so"
    IMPORTED_NO_SONAME TRUE)
add_library(arkscale_engine SHARED IMPORTED)
set_target_properties(arkscale_engine PROPERTIES
    IMPORTED_LOCATION "${CMAKE_CURRENT_SOURCE_DIR}/../../../libs/arm64-v8a/libarkscale_engine.so"
    IMPORTED_NO_SONAME TRUE)
target_include_directories(arkscale_bridge PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/../../../../smoke/include"
    "${CMAKE_CURRENT_SOURCE_DIR}/../../../../engine/include")
target_link_libraries(arkscale_bridge PUBLIC arkscale_smoke arkscale_engine libace_napi.z.so)
