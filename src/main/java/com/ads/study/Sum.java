package com.ads.study;

import com.google.common.collect.Lists;

import java.util.ArrayList;
import java.util.List;

/**
 * @Classname Sum
 * @Description TODO
 * @Created by kongshaokui
 * @Date 2019/12/1 18:53
 */
public class Sum {

    public static void main(String[] args) {

        int nums[] = {2,7,11,15,8,4,1,5,3,7};
        int target = 9;

        int[] ints = twoSum(nums, target);
    }

    public static int[] twoSum(int[] nums, int target) {
        int length = nums.length;
        for (int i = 0; i < length; i++) {
            for (int j = 0; j < length; j++) {
                if((nums[i] + nums[j])==target){
                    return new int[] { i, j };
                }
            }
        }
        throw new IllegalArgumentException("No two sum solution");
    }
}
