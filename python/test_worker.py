import unittest

from worker import fix_numbers


class FixNumbersTest(unittest.TestCase):
    def test_repairs_joined_decimal(self):
        self.assertEqual(fix_numbers("it's using like2 .8 gig."), "it's using like 2.8 gig.")
        self.assertEqual(fix_numbers("RAM is at2 .8 gig"), "RAM is at 2.8 gig")
        self.assertEqual(fix_numbers("Version3 .5 costs"), "Version 3.5 costs")
        self.assertEqual(fix_numbers("about12 .75 percent"), "about 12.75 percent")

    def test_repairs_split_decimal(self):
        self.assertEqual(fix_numbers("at 2 .8 gig"), "at 2.8 gig")

    def test_keeps_correct_text(self):
        for text in ["The M5 chip and MP3 files.", "It costs 4.99 dollars.", "Twelve apples. 5 more.", "Version 3.5"]:
            self.assertEqual(fix_numbers(text), text)


if __name__ == "__main__":
    unittest.main()
