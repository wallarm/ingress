rm -rf build
mkdir build
cd build
cmake -DBUILD_SHARED_LIBS=OFF ..
make -j`nproc` VERBOSE=1
sudo make install