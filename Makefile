.PHONY: clean

clean:
	rm -rf -- \
		mirageapp/_build \
		mirageapp/dist \
		mirageapp/duniverse \
		mirageapp/mirage
	rm -f -- \
		mirageapp/Makefile \
		mirageapp/dune \
		mirageapp/dune.build \
		mirageapp/dune.config \
		mirageapp/dune-project \
		mirageapp/dune-workspace
