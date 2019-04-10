# Uses gmake extensions.

# 1st detect the current OS.

ifeq ($(OS),Windows_NT)
  LIBS    += -lws2_32
else
  OS := $(shell uname 2>/dev/null || echo Unknown)
  ifeq ($(OS),Linux)
    CCFLAGS += -D LINUX
  endif
  ifeq ($(OS),Darwin)
    CCFLAGS += -D OSX
  endif
endif

HOSTTYPE := $(shell echo $$HOSTTYPE)

ifeq ($(HOSTTYPE),i686)
  INCLUDE += -I aPLib/lib/coff
  APLIB   += aPLib/lib/coff/aplib.lib
else
  INCLUDE += -I aPLib/lib/coff64
  APLIB   += aPLib/lib/coff64/aplib.lib
endif

# Then 

OBJECTS   = aplpak.o
OUTPUT    = aplpak
TARGETS   = $(OUTPUT)
LIBS     += 
CFLAGS   += -O2 $(INCLUDE)
LDFLAGS  += -s
CLEANED   = $(OBJECTS) $(TARGETS)
CC        = cc

.PHONY: all clean install

all: $(OBJECTS) $(TARGETS)

%.o: %.c
	$(CC) $(CFLAGS) -c -o $@ $<

aplpak: aplpak.o
	$(CC) $(LDFLAGS) aplpak.o $(APLIB) -o $@ $(LIBS)

clean:
	$(RM) $(CLEANED)

install: $(TARGETS)
	mkdir -p $(DSTDIR)/
	cp $(TARGETS) $(DSTDIR)/
