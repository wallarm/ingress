rm -rf build
mkdir build
cd build
cmake -DLIBXML2_WITH_PYTHON=OFF -DLIBXML2_WITH_LZMA=OFF -DBUILD_SHARED_LIBS=OFF ..
make -j`nproc` VERBOSE=1
sudo make install