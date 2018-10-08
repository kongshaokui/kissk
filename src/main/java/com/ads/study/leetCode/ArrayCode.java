package com.ads.study.leetCode;

import java.util.Collections;

/**
 * User: kismetkong@tcl.com
 * Date: 2018-09-26
 * Time: 14:21
 */
public class ArrayCode {


    /**
     * Remove Element
     * 移除数组中给定的value,并返回新的数据长度，要求不能新建另一数据。
     * @param array 数组
     * @param element 给定value值
     * @return 新数组长度
     */
    public static int removeElementI(String[] array,String element){
        int i=0,j=0;
        int size=array.length;
        for (;i<size;i++){
            if(array[i]==element){
                continue;
            }
            array[j]=array[i];
            j++;
        }
        return j;
    }


    /**
     * 移除有序数据重复的value,并返回新数组长度
     * Given a sorted array, remove the duplicates in place such that > each element
     * appear only once and return the new length.
     * @param array
     * @return
     */
    public static int removeElementII(String[] array){
        int i=1,j=0;
        int size=array.length;
        for (; i < size; i++) {
            if(array[i].equals(array[j])){
                continue;
            }
            j++;
            array[j]=array[i];
        }
        return j+1;
    }

    /**
     * 移除重复两次以上的元素，并返回新数组长度
     * Follow up for "Remove Duplicates": What if duplicates are allowed at most
     * twice?
     * For example, Given sorted array A = [1,1,1,2,2,3],
     * Your function should return length = 5, and A is now [1,1,2,2,3].
     * @return
     */
    public static int removeElementIII(String[] array){
        int i=1,j=0;
        int size=array.length;
        int tmp=0;
        for (; i < size; i++) {
            if(array[i].equals(array[j])){
                tmp++;
                if(tmp<2){
                    j++;
                    array[j]=array[i];
                }
                continue;
            }
            j++;
            array[j]=array[i];
            tmp=0;
        }
        return j+1;
    }

    /**
     * Given a non-negative number represented as an array of digits, plus one to
     * the number.
     * The digits are stored such that the most significant digit is at the head of the
     * list.
     * @param args
     * @return
     */
    public static int[] plusOne(int[] args){

        int size = args.length;
        for (int i = size-1; i >= 0 ; i--) {
            if(args[i]<9){
                args[i]++;
                continue;
            }
            args[i]=0;
        }

        if(args[0]==0){
            int[] ints = new int[size + 1];
            for (int i = size-1; i > 0 ; i--) {
                ints[i]=args[i];
            }
            ints[0]=1;
            return ints;
        }
        return args;
    }


    /**
     *  Given numRows, generate the first numRows of Pascal's triangle.
        For example, given numRows = 5, Return
     [
        [1],
        [1,1],
        [1,2,1],
        [1,3,3,1],
        [1,4,6,4,1],
        [1,5,10,10,5,1]
     ]
     * @param numRows
     */
    public static void pascalTriangle(int numRows){
        int[][] ints = new int[numRows][];
        //for ()
    }

    public static void main(String[] args) {
//        System.out.println(removeElementI(new String[]{"1", "2", "2", "3", "5","10"},"2"));
//        System.out.println(removeElementII(new String[]{"1", "2", "2", "3","4","4","5","10","20","20"}));
//        System.out.println(removeElementIII(new String[]{"1", "2", "2","2","3","3","4","4","5","10","20","20","20"}));
//        plusOne(new int[]{1, 2, 3, 4, 9, 9, 7});

    }
}
