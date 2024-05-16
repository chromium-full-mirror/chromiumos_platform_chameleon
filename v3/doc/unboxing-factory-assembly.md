# Chameleon v3 MP assembly and testing procedures
[TOC]

## Objective
Describes the process for assembly of every single Chameleon v3 at the factory.  
After assembly, the boards will be tested in reference to procedures in [Chameleon MP Factory Testing/QC].  
After testing, the board will be packed.  
The goal is that after the procedures, the board is ready to ship directly to the user.

## Reference Documents
[Chameleon MP Factory Testing/QC]  

## Required Parts

* Item A:  Chameleon v3 (1pc)

  * Top side

    ![](images/factory/item-a-top.png)

  * Bottom side

    ![](images/factory/item-a-bottom.jpg)

* Item B:  [Enclustra Mercury+ AA1 FPGA module], P/N ME-AA1-270-2I2-D11E (1pc)
  * Package
    ![](images/factory/item-b-package.jpg)

  * Top side
    ![](images/factory/item-b-top.jpg)

  * Bottom side
    ![](images/factory/item-b-bottom.jpg)

* Item C:  [Enclustra Mercury Heat Sink],  
  P/N ACC-HS4-SET (1pc)

  * Package
  * Content inside package
    ![](images/factory/item-c.jpg)

* Item D:  Acrylic fan plate (1pc)  
  (Item D:  風扇側壓克力板)

  ![](images/factory/item-d.jpg)

* Item E:  Acrylic bottom plate (1pc)  
  (Item E:  下側壓克力板)

  ![](images/factory/item-e.jpg)

* Item F:  Metal Female Threaded Hex Standoff M3, 10mm Long (1pc)  
  (Item F: 雙通六角螺柱, M3, 10mm)
  * [Local part](https://shopee.tw/%E7%8F%BE%E8%B2%A8%F0%9F%92%AF%EF%BC%88M3%EF%BC%89304%E4%B8%8D%E9%8F%BD%E9%8B%BC%E8%9E%BA%E6%9F%B1%E5%96%AE%E9%A0%AD%E5%85%AD%E8%A7%92%E8%9E%BA%E7%B5%B2%E6%9F%B1%E6%A9%9F%E7%AE%B1%E4%B8%BB%E6%9D%BF%E9%80%A3%E6%8E%A5%E6%9F%B1%E9%99%B0%E9%99%BD%E9%9A%94%E9%9B%A2%E6%9F%B1%E9%8A%85%E6%9F%B1-%E5%85%8D%E8%B2%BB%E9%96%8B%E7%A5%A8-%E6%94%AF%E6%8C%81%E6%AA%A2%E6%B8%AC-%E9%98%B2%E9%8F%BD%E8%80%90%E8%85%90-i.492162237.20676774124)

  ![](images/factory/item-f.png)

* Item G:  Pan Head Phillips Screws, 18-8 Stainless Steel M3, 6mm Long (1pc)  
  (Item G:  十字圓頭螺絲, M3, 6mm)

  ![](images/factory/item-g.png)

* Item H:  Metal Female Threaded Hex Standoff M3, 40mm Long (4pcs)  
  (Item H:  雙通六角螺柱, M3, 40mm)

  ![](images/factory/item-h.jpg)

* Item I:  Metal Male-Female Threaded Hex Standoff, 6mm Hex, M3, 10mm Long (4pcs)  
  (Item I:  單頭六角螺絲柱, 6mm外螺紋, M3, 10mm)

  ![](images/factory/item-i.jpg)

* Item J:  Stainless Steel Socket Head Screw, M3, 6 mm Long (8pcs)  
  (Item J:  內六角圓柱頭螺絲釘, M3, 6mm)

  ![](images/factory/item-j.png)

* Item K:  Stainless Steel Hex Nuts, M3, 1.8-2mm thickness (4pcs)  
  (Item K:  扁薄六角螺母, M3, 1.8-2mm厚度)

  ![](images/factory/item-k.png)

* Item L:  Pan Head Phillips Screws, 18-8 Stainless Steel M3, 16mm Long (4pc)  
  (Item L:  十字圓頭螺絲, M3, 16mm)

  ![](images/factory/item-l.png)

## Generate MAC Address Label (產生MAC地址標籤)
  1. Obtain the FPGA serial number from the package or bottom side of Item B:  [Enclustra Mercury+ AA1 FPGA module], **P/N ME-AA1-270-2I2-D11E**.  Serial numbers can be scanned or read by humans.  
  (在FPGA盒子或板子背面可獲得序號.  序號可以人工讀取或是掃描獲得)

     ![](images/factory/mac-label-1.jpg)
     ![](images/factory/mac-label-2.jpg)

  2. Enter the serial number (example SN212601) into spreadsheet column A.  
     MAC0 address will be generated in column B.  
     (將得到的序號填入 表格內的A欄.  舉例SN212601.  MAC0 地址會自動在B欄產生)

  3. Copy serial number (example SN212601) and MAC address (example 20:B0:F7:06:7C:F2) to a document to be printed.  The label should have both text and bar code.  Label size (15mm * 43mm max)  
  (將序號與MAC0 地址copy 到另一份文件並印出成為標籤.  標籤上需要同時有文字跟條碼.  貼紙最大尺寸為 15mm * 43 mm.)

     ![](images/factory/mac-label-4.png)

## Assembly Procedure (組裝流程)
Assemble the standoffs and FPGA module (六角螺柱與FPGA組裝流程)

1. Install **Item I:  Metal Male-Female Threaded Hex Standoff, 6mm Hex, M3, 10mm Long** at the four corners from the bottom side of **Item A: Chameleon v3** and use **Item H: Metal Female Threaded Hex Standoff M3, 40mm Long** to screw tight on **Item A: Chameleon v3**  
  (將Item I:  單頭六角螺絲柱, 6mm外螺紋, M3, 10mm 從Item A:  Chameleon v3 四週的孔從下方插入, 用Item H:  雙通六角螺柱, M3, 40mm從上方鎖緊)

  ![](images/factory/assembly-1.jpg)

2. Repeat above instruction for all 4 corners  
  (四個角落都重複步驟1的動作)

  ![](images/factory/assembly-2.jpg)

3. Assemble **Item F: Metal Female Threaded Hex Standoff M3, 10mm Long** and **Item G:  Pan Head Phillips Screws, 18-8 Stainless Steel M3, 6mm Long**.  
  (將Item F: 雙通六角螺柱, M3, 10mm 從下方, Item G:  十字圓頭螺絲, M3, 6mm在下方, 鎖緊)

  ![](images/factory/assembly-3a.jpg)
  ![](images/factory/assembly-3b.jpg)

4. Unpack **Item B:  [Enclustra Mercury+ AA1 FPGA module], P/N ME-AA1-270-2I2-D11E** and **Item C: ACC-HS4-SET**  
  (將Item B:  [Enclustra Mercury+ AA1 FPGA module], P/N ME-AA1-270-2I2-D11E 與 Item C:  Enclustra Mercury Heat Sink, P/N ACC-HS4-SET 拆開)

  ![](images/factory/assembly-4a.jpg)
  ![](images/factory/item-c.jpg)

5. Peel the 29 x 29 x 1.0T thermal pad from the larger backing, align and place on top of the FPGA.  
  (將29 x 29 x 1.0T散熱片對齊並貼在FPGA 上面)

![](images/factory/assembly-5.jpg)

6. Remove the other plastic backing.  
  (將上方塑膠片撕開)

  ![](images/factory/assembly-6.jpg)

7. Line up the heatsink with the thermal pad and the mounting holes.  Place heatsink on the FPGA module.  
  (將散熱器與散熱片/四個孔對齊, 後平整放上去)

  ![](images/factory/assembly-7.png)

8. Screw **Item L: Pan Head Phillips Screws, 18-8 Stainless Steel M3, 16mm Long** into the 4 inner holes  
  (將Item L:  十字圓頭螺絲, M3, 16mm 鎖上散熱器上的四個孔)

  ![](images/factory/assembly-8a.png)
  ![](images/factory/assembly-8b.png)

9. Flip the FPGA module + heat sink upside down and insert the 4 spacers from **Item C: Enclustra Mercury Heat Sink, P/N ACC-HS4-SET**  
  (將FPGA模組+散熱器 翻面, 並將4個圓孔墊片放在螺絲的位置)

  ![](images/factory/assembly-9a.png)
  ![](images/factory/assembly-9b.jpg)

10. Flip **Item A:  Chameleon v3** upside down.  Insert the FPGA with heatsink from the bottom onto **Item A:  Chameleon v3**.  The connector orientation needs to align.  
  (將Item A:  Chameleon v3翻面.  從下方將FPGA模組+散熱器對準四個孔插入.  注意需對齊白色連接器的方向)

  ![](images/factory/assembly-10.jpg)

11. Press the heatsink against Chameleon V3, so the connectors are fully inserted  
  (將散熱器往Chameleon V3 方向推.  讓連接器緊密接合.  下方有附緊密接合跟未接好的圖片)

  ![](images/factory/assembly-11a.jpg)
  ![](images/factory/assembly-11b.jpg)

12. Screw **Item K:  Stainless Steel Hex Nuts, M3, 1.8-2mm thickness** to **Item G:  Pan Head Phillips Screws, 18-8 Stainless Steel M3, 17mm Long**.  
  (將Item K:  扁薄六角螺母, M3, 1.8-2mm厚度 從背面鎖上Item G:  十字圓頭螺絲, M3, 6mm)

  ![](images/factory/assembly-12a.png)
  ![](images/factory/assembly-12b.png)
  ![](images/factory/assembly-12c.png)

13. Place the fan on top of the heatsink with the wires protruding at the upper-right corner (considering the horizontal connector on the FPGA module to be the bottom edge). Use the longest screws to secure the fan to the heatsink.  
  (將風扇放到散熱器上方, 電線需要在右上角.  用最長的M3螺絲鎖上散熱器去)

14. Connect the fan power cable to the 3-pin connector near the power jack.  
  (將風扇接頭接上右邊的連結器)

  ![](images/factory/assembly-14.jpg)

15. Attach SN and MAC address label on the RJ45 connectors  (J1/J3)  
  (將序號與MAC地址的標籤貼上RJ45連接器上方)

  ![](images/factory/assembly-15.jpg)

## Assemble the acrylic plates (壓克力組裝)

  1. Peel off the protection films on the inner side of **Item D:  Acrylic fan plate**  
    (將Item D:  風扇側壓克力板的保護膜撕掉, 只撕掉內側)

  ![](images/factory/assembly-acrylic-1.jpg)

  2. Place **Item D:  Acrylic fan plate** on top of the standoffs with all 4 holes aligned  
    (將Item D:  風扇側壓克力板放置到六角螺柱上, 開孔需對齊)

  ![](images/factory/assembly-acrylic-2.jpg)

  3. Use **Item J:  Stainless Steel Socket Head Screw, M3, 5 mm Long** to secure the fan plate to the standoffs (all 4 standoffs)  
    (用Item J:  圓柱頭螺絲釘, M3, 5mm將壓克力板鎖上六角螺柱)

  4. Flip the board so it is upside down  
    (將板子翻到背面)

  5. Peel off the protection films on the inner side of **Item E:  Acrylic bottom plate**  
    (將Item E:  下側壓克力板的保護膜撕掉, 只撕掉內側)

  ![](images/factory/assembly-acrylic-5.jpg)

  6. Place **Item E:  Acrylic bottom plate** on top of the standoffs with all 4 holes aligned  
    (將Item E:  下側壓克力板放置到六角螺柱上, 開孔需對齊)

  ![](images/factory/assembly-acrylic-6.jpg)

  7. Use **Item J:  Stainless Steel Socket Head Screw, M3, 6 mm Long** to secure the bottom plate to the standoffs (all 4 standoffs)  
    (用Item J:  內六角圓柱頭螺絲釘, M3, 6mm將壓克力板鎖上六角螺柱)

  8. Fully assembled device should look like this  
    (完整組裝後會如下圖)

  ![](images/factory/assembly-acrylic-8.png)

## Testing Procedure
See [Chameleon MP Factory Testing/QC]

## Packing procedure
Things in the box:

  * Chameleon

  * Chameleon Power supply
    * [pcstore.com.tw](https://seller.pcstore.com.tw/S121921457/C1165264518.htm)
      ![](images/factory/item-psu.png)

  * No SD card as this is not on the BOM

## Appendix
* Link to local parts
  * Chameleon power supply (12V/5A)
    * [pcstore.com.tw](https://seller.pcstore.com.tw/S121921457/C1165264518.htm)
    * [shopee.tw](https://shopee.tw/%E5%BB%BA%E8%88%88-LITEON-DC-12V-5A-%E8%B6%B3%E7%93%A6-%E8%AE%8A%E5%A3%93%E5%99%A8-%E7%A9%A9%E5%A3%93%E5%99%A8-%E7%9B%A3%E6%8E%A7%E9%9B%BB%E6%BA%90-LED%E9%9B%BB%E6%BA%90-%E5%9C%8B%E9%9A%9B%E8%AA%8D%E8%AD%89-R33275-i.7143700.7419132380?sp_atk=2d7c79a5-4ccc-49b6-9e9f-b91eb825f0e8&xptdk=2d7c79a5-4ccc-49b6-9e9f-b91eb825f0e8)
  * Item D:  Acrylic fan plate (1pc)
    * [shihhongacrylic.com](https://shihhongacrylic.com/)
    * Design file
  * Item E:  Acrylic bottom plate (1pc)
    * [shihhongacrylic.com](https://shihhongacrylic.com/)
    * Design file
  * Item F:  Metal Female Threaded Hex Standoff M3, 10mm Long (1pc)
  * Item G:  Pan Head Phillips Screws, 18-8 Stainless Steel M3, 6mm Long (1pc)
  * Item H:  Metal Female Threaded Hex Standoff M3, 40mm Long (4pcs)
  * Item I:  Metal Male-Female Threaded Hex Standoff, 6mm Hex, M3, 10mm Long (4pcs)
  * Item J:  Stainless Steel Socket Head Screw, M3, 5 mm Long (8pcs)
  * Item K:  Stainless Steel Hex Nuts, M3, 1.8-2mm thickness (4pcs)
  * Item L:  Pan Head Phillips Screws, 18-8 Stainless Steel M3, 16mm Long (4pc)

[Chameleon MP Factory Testing/QC]: unboxing-factory-testing.md
[Enclustra Mercury+ AA1 FPGA module]: https://www.enclustra.com/en/products/system-on-chip-modules/mercury-aa1/
[Enclustra Mercury Heat Sink]: https://www.enclustra.com/en/products/heat-sinks/mercury-heat-sinks/
