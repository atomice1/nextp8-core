# Makefile for UART test
# Copyright (C) 2025 Chris January
# GPL-3

CXX = g++
CXXFLAGS = -Wall -Wextra -O2 -g
LDFLAGS = 

SRCS = uart.cpp uart_test.cpp
OBJS = $(SRCS:.cpp=.o)
TARGET = uart_test

all: $(TARGET)

$(TARGET): $(OBJS)
	$(CXX) $(CXXFLAGS) -o $@ $^ $(LDFLAGS)

%.o: %.cpp
	$(CXX) $(CXXFLAGS) -c -o $@ $<

uart.o: uart.cpp uart.h
uart_test.o: uart_test.cpp uart.h

clean:
	rm -f $(OBJS) $(TARGET)

run: $(TARGET)
	./$(TARGET)

.PHONY: all clean run
