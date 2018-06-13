SRC = scres.swift

BIN = swiftc

OUTPUT = scres

FLAGS= -O -o

default:
	$(BIN) $(FLAGS) $(OUTPUT) $(SRC)

clean:
	rm $(OUTPUT)

