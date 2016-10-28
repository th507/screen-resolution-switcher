SRC = scres.swift

BIN = swiftc

OUTPUT = retina

FLAGS= -O -o

default:
	$(BIN) $(FLAGS) $(OUTPUT) $(SRC)

clean:
	rm $(OUTPUT)

