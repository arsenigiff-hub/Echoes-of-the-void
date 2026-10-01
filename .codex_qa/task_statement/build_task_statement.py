from copy import deepcopy
from pathlib import Path
import zipfile

from lxml import etree


REFERENCE = Path(r"C:\Users\arseni\Downloads\Пример постановки задачи (1).docx")
OUTPUT = Path(r"D:\godot\GodotGame-main\Постановка задачи ECHOES OF THE VOID.docx")

W_NS = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
XML_NS = "http://www.w3.org/XML/1998/namespace"
W = f"{{{W_NS}}}"


BODY_PARAGRAPHS = [
    (
        "Разработать трехмерную компьютерную игру «ECHOES OF THE VOID» в жанре психологического "
        "космического хоррора от первого лица. Программный продукт должен быть реализован на базе "
        "Godot Engine 4.x с использованием языка GDScript 2.0 и физического движка Jolt Physics. "
        "Игра предназначена для пользователей персональных компьютеров, интересующихся научной "
        "фантастикой, атмосферным исследованием и нестандартными механиками перемещения."
    ),
    (
        "Основная задача игрока заключается в исследовании аварийного челнока, поиске и расшифровке "
        "аномальных радиосигналов, устранении возникающих неисправностей и поддержании работоспособности "
        "бортовых систем. Игровой процесс должен объединять перемещение по внутренним помещениям, "
        "взаимодействие с физическими приборами, работу с бортовым терминалом и выходы в открытый космос."
    ),
    (
        "Реализовать главное меню с командами запуска новой игры, продолжения, изменения настроек и "
        "выхода. После выбора новой игры обеспечить плавный кинематографический переход к вступительной "
        "сцене, а после ее завершения — загрузку основной игровой сцены. Предусмотреть внутриигровое меню "
        "паузы с возможностью возобновить сеанс или вернуться в главное меню."
    ),
    (
        "Обеспечить управление персонажем от первого лица: перемещение клавишами WASD, обзор мышью, "
        "прыжок, включение фонаря и взаимодействие с объектами через направленный луч. При работе с "
        "консолями временно блокировать перемещение, плавно переводить камеру к прибору и возвращать "
        "управление после завершения взаимодействия."
    ),
    (
        "Разработать подсистему радиоперехвата с настройкой частоты в диапазоне от 100.00 до 999.99 МГц. "
        "По мере приближения к целевой частоте изменять уровень шума и форму осциллограммы. При удержании "
        "резонанса в течение трех секунд фиксировать сигнал, сохранять радиопакет и предоставлять возможность "
        "его последующей расшифровки и воспроизведения на терминале."
    ),
    (
        "Реализовать систему аварий челнока и безопасного шлюзования. Внешний люк не должен открываться, "
        "пока внутренний люк открыт или в камере сохраняется давление. После декомпрессии переключать "
        "звуковое окружение на внутришлемный канал и переводить контроллер игрока в режим внекорабельной "
        "деятельности с перемещением при помощи захватов за элементы корпуса."
    ),
    (
        "Во время внекорабельного выхода учитывать запас кислорода, инерционное движение и допустимое "
        "расстояние до ремонтной точки. Ремонт выполнять только при надежной фиксации игрока у корпуса. "
        "После восстановления поврежденной системы снять аварийную сигнализацию, обеспечить возвращение "
        "в шлюз, закрытие внешнего люка и восстановление нормального давления."
    ),
    (
        "Сформировать атмосферу изоляции с помощью контрастного аварийного освещения, ретро-дизеринга, "
        "радиошумов и физически обоснованного звука в вакууме. Предусмотреть сохранение игрового прогресса "
        "и состояния систем челнока. Обеспечить стабильную работу приложения в Windows 10 и Windows 11 "
        "с целевой частотой не менее 60 кадров в секунду при разрешении 1920×1080."
    ),
]

LIST_ITEMS = [
    "Реализовать контекстные подсказки для клавиш взаимодействия, фонаря и захвата поверхности.",
    "Предусмотреть журнал обнаруженных сигналов с указанием состояния захвата и расшифровки радиопакета.",
    "Добавить несколько типов неисправностей: отказ антенны, нарушение энергоснабжения и сбой продувочного клапана.",
    "Отображать на шлемовом интерфейсе запас кислорода и индикатор возможности захвата поверхности.",
    "Сохранять текущий прогресс, запас кислорода, состояние систем и перечень найденных сигналов в формате JSON.",
    "Провести функциональное, интеграционное и нагрузочное тестирование переходов между сценами, физики захватов и работы шлюза.",
]


def replace_existing_text(paragraph, text):
    text_nodes = paragraph.xpath(".//w:t", namespaces={"w": W_NS})
    if not text_nodes:
        run = etree.SubElement(paragraph, W + "r")
        text_node = etree.SubElement(run, W + "t")
        text_node.text = text
        return
    text_nodes[0].text = text
    for node in text_nodes[1:]:
        node.text = ""


def clone_paragraph(template, text):
    paragraph = deepcopy(template)
    runs = paragraph.xpath("./w:r", namespaces={"w": W_NS})
    run_template = deepcopy(runs[0]) if runs else etree.Element(W + "r")
    for child in list(run_template):
        if child.tag != W + "rPr":
            run_template.remove(child)
    text_node = etree.SubElement(run_template, W + "t")
    if text.startswith(" ") or text.endswith(" "):
        text_node.set(f"{{{XML_NS}}}space", "preserve")
    text_node.text = text
    for run in runs:
        paragraph.remove(run)
    paragraph.append(run_template)
    return paragraph


def build_document_xml(source_xml):
    parser = etree.XMLParser(remove_blank_text=False)
    root = etree.fromstring(source_xml, parser)
    body = root.find(".//" + W + "body")
    paragraphs = [child for child in body if child.tag == W + "p"]

    replace_existing_text(paragraphs[0], "ECHOES OF THE VOID")
    replace_existing_text(paragraphs[1], "Постановка задачи:")

    body_template = paragraphs[2]
    lead_template = paragraphs[7]
    list_template = paragraphs[8]
    empty_template = paragraphs[12]

    for paragraph in paragraphs[2:]:
        body.remove(paragraph)

    section_properties = body.find(W + "sectPr")
    insertion_index = body.index(section_properties)
    new_paragraphs = [clone_paragraph(body_template, text) for text in BODY_PARAGRAPHS]
    last_body_properties = new_paragraphs[-1].find(W + "pPr")
    if last_body_properties is not None:
        keep_lines = last_body_properties.find(W + "keepLines")
        if keep_lines is None:
            keep_lines = etree.SubElement(last_body_properties, W + "keepLines")
        keep_lines.set(W + "val", "1")
    new_paragraphs.append(
        clone_paragraph(
            lead_template,
            "Для игры «ECHOES OF THE VOID» реализовать следующие дополнительные функции:",
        )
    )
    new_paragraphs.extend(clone_paragraph(list_template, text) for text in LIST_ITEMS)
    new_paragraphs.append(clone_paragraph(empty_template, ""))

    for offset, paragraph in enumerate(new_paragraphs):
        body.insert(insertion_index + offset, paragraph)

    return etree.tostring(root, xml_declaration=True, encoding="UTF-8", standalone=True)


def main():
    with zipfile.ZipFile(REFERENCE, "r") as source:
        document_xml = build_document_xml(source.read("word/document.xml"))
        with zipfile.ZipFile(OUTPUT, "w") as target:
            for item in source.infolist():
                data = document_xml if item.filename == "word/document.xml" else source.read(item.filename)
                target.writestr(item, data)
    print(OUTPUT)


if __name__ == "__main__":
    main()
