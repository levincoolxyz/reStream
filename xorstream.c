#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <signal.h>
#include <assert.h>

static void usage() {
    fprintf(stderr, "XOR stream\n");
	fprintf(stderr, "Perform xor between stdin and a reference file, and\n");
	fprintf(stderr, "return result to stdout while saving stdin stream.\n");
	fprintf(stderr, "\n");
	fprintf(stderr, "Usage: \n");
	fprintf(stderr, "xorstream ref_file new_file flag\n");
	fprintf(stderr, "Where:\n");
	fprintf(stderr, "    ref_file         the file to be xored\n");
    fprintf(stderr, "    new_file         the file storing stdin\n");
    fprintf(stderr, "    flag[d]          flag for decoding (one less memcpy)\n");
	fprintf(stderr, "\n");
	fprintf(stderr, "!!!WARNING: Not fool proof only for use with rmStream!!!\n");
}

volatile sig_atomic_t stop;

void sigINThandle(int signum) {
    stop = 1;
}

int main(int argc, char *argv[]) {

	// fprintf(stderr, "argc = %d\n", argc);
	// fprintf(stderr, "argv0 = %s\n", argv[0]);
	// fprintf(stderr, "argv1 = %s\n", argv[1]);
    // fprintf(stderr, "argv2 = %s\n", argv[2]);

	if (argc != 4) {
    	usage();
        return 1;
	}

    FILE *fr,*fw;

	fr=fopen(argv[1],"rb"); // reference file read stream
    fw=fopen(argv[2],"wb"); // reference file write stream

	if (fr == NULL) {
		fprintf(stderr, "ERROR: Invalid Reference File Path!\n\n");
		usage();
		return 1;
	}

    size_t inSize,outSize;
    size_t blockSize=5271552; // 1408*1872*2
    // fprintf(stderr,"blockSize = %lu\n", blockSize);

    char *buf_in,*buf_ref;
    buf_in=malloc(blockSize);
    buf_ref=malloc(blockSize);

    signal(SIGINT, sigINThandle);

    inSize=fread(buf_ref,1,blockSize,fr); // Read ref_file to buf_ref
    // fprintf(stderr,"ref_file = %lu\n", inSize);
    assert(inSize <= blockSize);
    // if (inSize == 0) break;

    while (!stop) {
        inSize=fread(buf_in,1,blockSize,stdin); // Read stdin to buf_in
        // fprintf(stderr,"stdin = %lu\n", inSize);
        assert(inSize <= blockSize);
        if (inSize == 0) break;

        for (size_t x=0; x<blockSize; ++x)
            buf_ref[x] = ((char) buf_ref[x] ^ (char) buf_in[x]); // write XOR to buf_ref

        outSize=fwrite(buf_ref,1,blockSize,stdout); // write buf_ref to stdout
        assert(outSize <= blockSize);

        if (strcmp(argv[3],"d"))
            memcpy(buf_ref,buf_in,blockSize);
    }

    outSize=fwrite(buf_in,1,blockSize,fw); // write buf_in to new_file
    assert(outSize <= blockSize);

    fclose(fr);
    fclose(fw);
    free(buf_in);
    free(buf_ref);
    return 0;
}