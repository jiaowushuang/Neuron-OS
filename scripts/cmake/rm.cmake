file(GLOB build_dir_contents ${CMAKE_BINARY_DIR}/*)
foreach(file ${build_dir_contents})
  if (EXISTS ${file})
     file(REMOVE_RECURSE ${file})
  endif()
endforeach(file)