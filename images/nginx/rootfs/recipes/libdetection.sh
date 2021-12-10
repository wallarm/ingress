rm -rf build
mkdir build
cd build
cmake -DENABLE_STATIC=ON ..
make -j`nproc` VERBOSE=1
sudo make install