import pytest
import os
from backend import parse_filename, get_year, paper_group_of, group_papers, build_folders


class TestParseFilename:
    def test_valid_qp(self):
        r = parse_filename("9701_s21_qp_12.pdf")
        assert r == {"subject": "9701", "sy": "s21", "type": "qp", "number": "12", "filename": "9701_s21_qp_12.pdf"}

    def test_valid_ms(self):
        r = parse_filename("0625_w23_ms_1.pdf")
        assert r == {"subject": "0625", "sy": "w23", "type": "ms", "number": "1", "filename": "0625_w23_ms_1.pdf"}

    def test_no_number(self):
        r = parse_filename("9702_m23_qp.pdf")
        assert r is not None
        assert r["number"] == ""

    def test_standalone_type_ci(self):
        r = parse_filename("0625_s23_ci_3.pdf")
        assert r == {"subject": "0625", "sy": "s23", "type": "ci", "number": "3", "filename": "0625_s23_ci_3.pdf"}

    def test_invalid_filename(self):
        assert parse_filename("readme.txt") is None
        assert parse_filename("") is None


class TestGetYear:
    def test_summer(self):
        assert get_year("s21") == "2021"

    def test_winter(self):
        assert get_year("w23") == "2023"

    def test_march(self):
        assert get_year("m24") == "2024"

    def test_unknown_prefix(self):
        assert get_year("x99") == "unknown"  # non-standard prefix starts with unknown char

    def test_short(self):
        assert get_year("s") == "unknown"


class TestPaperGroupOf:
    def test_empty(self):
        assert paper_group_of("") == 0

    def test_single_digit(self):
        assert paper_group_of("1") == 1
        assert paper_group_of("6") == 6

    def test_double_digit(self):
        assert paper_group_of("12") == 1
        assert paper_group_of("21") == 2
        assert paper_group_of("99") == 9


class TestGroupPapers:
    def test_simple_pair(self):
        rows = [
            {"file": "9701_s23_qp_1.pdf"},
            {"file": "9701_s23_ms_1.pdf"},
        ]
        g = group_papers(rows)
        assert len(g) == 1
        assert g[0]["qp"] == "9701_s23_qp_1.pdf"
        assert g[0]["ms"] == "9701_s23_ms_1.pdf"

    def test_qp_only(self):
        rows = [{"file": "9701_s23_qp_1.pdf"}]
        g = group_papers(rows)
        assert len(g) == 1
        assert g[0]["qp"] == "9701_s23_qp_1.pdf"
        assert g[0]["ms"] is None

    def test_different_numbers_not_paired(self):
        rows = [
            {"file": "9701_s23_qp_1.pdf"},
            {"file": "9701_s23_ms_2.pdf"},
        ]
        g = group_papers(rows)
        assert len(g) == 2  # not paired

    def test_standalone_types_ignored(self):
        rows = [
            {"file": "0625_s23_ci_3.pdf"},
            {"file": "9701_s23_qp_1.pdf"},
        ]
        g = group_papers(rows)
        assert len(g) == 2

    def test_sorting_by_paper_group(self):
        rows = [
            {"file": "9701_s23_qp_21.pdf"},
            {"file": "9701_s23_qp_1.pdf"},
            {"file": "9701_s23_qp_12.pdf"},
        ]
        g = group_papers(rows)
        numbers = [x["number"] for x in g]
        assert numbers == ["1", "12", "21"]


class TestBuildFolders:
    def test_merge(self):
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            folders = build_folders([{"sy": "s23"}], tmp, merge=True)
            assert folders == {"root": tmp}

    def test_no_merge(self):
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            groups = [{"sy": "s23"}, {"sy": "w24"}]
            folders = build_folders(groups, tmp, merge=False)
            assert "2023" in folders
            assert "2024" in folders
            assert os.path.isdir(folders["2023"]["qp"])
            assert os.path.isdir(folders["2023"]["ms"])
