test:
	nvim --headless -c "PlenaryBustedFile tests/$(FILE)" -c "qa!"

test-all:
	nvim --headless -c "PlenaryBustedDirectory tests/" -c "qa!"
