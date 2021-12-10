export NSSHARED=`realpath .`/debian/buildsystem
export BUILD_CC=clang
export PREFIX=`realpath .`/out


make -j`nproc` SHELL="sh -x" COMPONENT_TYPE=lib-shared
make install COMPONENT_TYPE=lib-shared
sudo cp -a -v out/* /usr/local