CC = gcc
CFLAGS = -Wall -Wextra -Wno-implicit-fallthrough -std=gnu23 -fPIC -O2
LDFLAGS = -shared -Wl,--wrap=malloc -Wl,--wrap=calloc -Wl,--wrap=realloc -Wl,--wrap=reallocarray -Wl,--wrap=free -Wl,--wrap=strdup -Wl,--wrap=strndup

TARGET = librstack.so
OBJS = rstack.o memory_tests.o

EXAMPLE = rstack_example
EXAMPLE_OBJ = rstack_example.o

.PHONY: all clean example

all: $(TARGET)

$(TARGET): $(OBJS)
	$(CC) $(LDFLAGS) -o $@ $(OBJS)

rstack.o: rstack.c rstack.h structs.h
	$(CC) $(CFLAGS) -c rstack.c -o rstack.o

memory_tests.o: memory_tests.c memory_tests.h
	$(CC) $(CFLAGS) -c memory_tests.c -o memory_tests.o

# ===== example =====

example: $(TARGET) $(EXAMPLE)

$(EXAMPLE): $(EXAMPLE_OBJ) $(TARGET)
	$(CC) -o $@ $(EXAMPLE_OBJ) -L. -lrstack -Wl,-rpath,.

$(EXAMPLE_OBJ): rstack_example.c rstack.h
	$(CC) $(CFLAGS) -c rstack_example.c -o rstack_example.o

# ===== clean =====

clean:
	rm -f $(OBJS) $(TARGET) $(EXAMPLE_OBJ) $(EXAMPLE)
