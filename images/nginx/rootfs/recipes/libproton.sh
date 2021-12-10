rm -rf build
mkdir build
cd build
cmake -DBUILD_TESTING=off ..
make -j`nproc` VERBOSE=1
sudo make install